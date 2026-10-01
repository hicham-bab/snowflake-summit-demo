#!/usr/bin/env python3
"""
Generate the raw-layer seed CSVs for atlas_platform.

Replaces the Snowflake GENERATOR()-based models under models/generate/ with
deterministic, version-controlled seeds (fixed RNG seed, byte-identical on
re-run). Reproduces the same row counts, seasonality buckets, and business
rules those SQL models documented, reading product/campaign reference data
from the existing catalog_*.csv seeds so IDs stay in sync.

One change from the original generator: raw_order_items now emits
item_count line items per order (1-5, matching raw_orders.item_count)
instead of exactly one row per order -- the GENERATOR(ROWCOUNT => 1) cross
join in the original SQL never actually varied item count despite the
model's own docstring, and int_orders_enriched already aggregates revenue
from order_items rather than trusting order.item_count, so this is a
clean fix, not a departure duly flagged in the PR.

Run: python3 scripts/generate_seed_data.py
"""

import csv
import hashlib
import os
import random
from datetime import date, datetime, timedelta

REPO_ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SEEDS_DIR = os.path.join(REPO_ROOT, "seeds")
RNG = random.Random(42)

ANCHOR_DATE = date(2026, 6, 16)
ANCHOR_TS = "2026-06-16T00:00:00Z"
ORDER_WINDOW_START = date(2025, 6, 1)

N_CUSTOMERS = 12000
N_ORDERS = 300000
N_EVENTS = 500000


def seed_path(filename):
    return os.path.join(SEEDS_DIR, filename)


def write_csv(path, header, rows):
    with open(path, "w", newline="") as f:
        w = csv.writer(f)
        w.writerow(header)
        w.writerows(rows)
    print(f"wrote {len(rows):>7,} rows -> {os.path.relpath(path, REPO_ROOT)}")


def read_csv_dicts(filename):
    with open(seed_path(filename), newline="") as f:
        return list(csv.DictReader(f))


def iso(d):
    return d.isoformat()


def weighted_choice(options_with_cutoffs):
    """options_with_cutoffs: list of (cumulative_pct_upper_bound, value), sorted ascending."""
    r = RNG.uniform(0, 100)
    for cutoff, value in options_with_cutoffs:
        if r <= cutoff:
            return value
    return options_with_cutoffs[-1][1]


# ===========================================================================
# raw_customers.csv -- 12,000 synthetic customers
# ===========================================================================
FIRST_NAMES = [
    "Emma", "Liam", "Olivia", "Noah", "Ava", "William", "Sophia", "James",
    "Isabella", "Oliver", "Mia", "Benjamin", "Charlotte", "Elijah", "Amelia",
    "Lucas", "Harper", "Mason", "Evelyn", "Logan",
]
LAST_NAMES = [
    "Smith", "Johnson", "Williams", "Brown", "Jones", "Garcia", "Miller",
    "Davis", "Rodriguez", "Martinez", "Hernandez", "Lopez", "Gonzalez",
    "Wilson", "Anderson", "Thomas", "Taylor", "Moore", "Jackson", "Martin",
    "Lee", "Perez", "Thompson", "White", "Harris",
]
EMAIL_DOMAINS = ["gmail.com", "yahoo.com", "outlook.com", "icloud.com", "hotmail.com", "proton.me"]
CITY_STATE = [
    ("New York", "NY"), ("Los Angeles", "CA"), ("Chicago", "IL"),
    ("Houston", "TX"), ("Phoenix", "AZ"), ("Philadelphia", "PA"),
]
ACQUISITION_CHANNELS = ["paid_search", "paid_social", "organic", "referral"]
SEGMENT_WEIGHTS = [(5, "VIP"), (25, "Premium"), (60, "Regular"), (100, "Budget")]


def generate_customers():
    rows = []
    for i in range(N_CUSTOMERS):
        customer_id = i + 1
        first = FIRST_NAMES[i % len(FIRST_NAMES)]
        last = LAST_NAMES[i % len(LAST_NAMES)]
        domain = EMAIL_DOMAINS[i % len(EMAIL_DOMAINS)]
        city, state = CITY_STATE[i % len(CITY_STATE)]
        segment = weighted_choice(SEGMENT_WEIGHTS)
        channel = ACQUISITION_CHANNELS[i % len(ACQUISITION_CHANNELS)]
        acquisition_date = ANCHOR_DATE - timedelta(days=RNG.randint(1, 1460))
        age = RNG.randint(18, 65)
        gender = "M" if RNG.randint(1, 2) == 1 else "F"
        is_sms_subscribed = RNG.randint(1, 100) <= 35

        rows.append([
            customer_id, first, last,
            f"{first.lower()}.{last.lower()}{customer_id}@{domain}",
            city, state, segment, channel, iso(acquisition_date), age, gender,
            "true", str(is_sms_subscribed).lower(), ANCHOR_TS, ANCHOR_TS,
        ])

    write_csv(
        seed_path("raw_customers.csv"),
        ["customer_id", "first_name", "last_name", "email", "city", "state",
         "customer_segment", "acquisition_channel", "acquisition_date", "age",
         "gender", "is_email_subscribed", "is_sms_subscribed", "created_at", "updated_at"],
        rows,
    )


# ===========================================================================
# raw_orders.csv -- ~300,000 orders, June 2025 through June 2026
# ===========================================================================
PAYMENT_WEIGHTS = [(52, "credit_card"), (75, "debit_card"), (88, "paypal"), (95, "apple_pay"), (100, "google_pay")]
TRAFFIC_WEIGHTS = [(22, "paid_search"), (42, "paid_social"), (58, "organic"), (70, "email"),
                   (82, "direct"), (90, "affiliate"), (100, "referral")]


def order_date_offset(idx100):
    if idx100 < 4:
        return RNG.randint(177, 183)
    if idx100 < 20:
        return RNG.randint(153, 213)
    if idx100 < 28:
        return RNG.randint(214, 244)
    if idx100 < 35:
        return RNG.randint(244, 319)
    return RNG.randint(0, 379)


def generate_orders():
    rows = []
    orders_meta = []  # (order_id, order_date, item_count, discount_amount) for order_items/returns
    for i in range(N_ORDERS):
        order_id = i + 1
        idx100 = i % 100

        order_date = ORDER_WINDOW_START + timedelta(days=order_date_offset(idx100))
        customer_id = RNG.randint(1, N_CUSTOMERS)

        store_roll = RNG.randint(1, 100)
        if store_roll <= 38:
            store_id = 20
        elif store_roll <= 55:
            store_id = 21
        else:
            store_id = RNG.randint(1, 19)

        if idx100 < 8:
            status = "cancelled"
        elif idx100 < 15:
            status = "returned"
        else:
            status = "completed"

        discount_amount = round(RNG.uniform(5.0, 30.0), 2) if idx100 < 22 else 0.00
        payment_method = weighted_choice(PAYMENT_WEIGHTS)
        campaign_id = RNG.randint(1, 30) if idx100 < 32 else ""
        traffic_source = weighted_choice(TRAFFIC_WEIGHTS)
        item_count = RNG.randint(1, 5)
        ordered_at = datetime.combine(order_date, datetime.min.time()) + timedelta(minutes=RNG.randint(0, 1380))

        rows.append([
            order_id, iso(order_date), customer_id, store_id, status,
            f"{discount_amount:.2f}", payment_method, campaign_id, traffic_source,
            item_count, ordered_at.isoformat() + "Z", ANCHOR_TS,
        ])
        orders_meta.append((order_id, order_date, customer_id, store_id, status, item_count, discount_amount))

    write_csv(
        seed_path("raw_orders.csv"),
        ["order_id", "order_date", "customer_id", "store_id", "status", "discount_amount",
         "payment_method", "campaign_id", "traffic_source", "item_count", "ordered_at", "_loaded_at"],
        rows,
    )
    return orders_meta


# ===========================================================================
# raw_order_items.csv -- one row per order_id x item_count (1-5 items/order)
# ===========================================================================
PRODUCT_TIER_WEIGHTS = [(60, (1, 20)), (85, (21, 50)), (100, (51, 80))]


def generate_order_items(orders_meta, products_by_id):
    rows = []
    order_item_id = 0
    for order_id, order_date, customer_id, store_id, status, item_count, discount_amount in orders_meta:
        for _ in range(item_count):
            order_item_id += 1
            lo, hi = weighted_choice(PRODUCT_TIER_WEIGHTS)
            product_id = RNG.randint(lo, hi)
            base_price = products_by_id[product_id]
            unit_price = round(base_price * (1 + RNG.uniform(-0.05, 0.05)), 2)
            quantity = RNG.randint(1, 4)

            line_discount = round(discount_amount / item_count, 2) if discount_amount > 0 else 0.00
            line_gross = round(unit_price * quantity, 2)
            line_net = round(line_gross - line_discount, 2)

            rows.append([
                order_item_id, order_id, product_id, quantity,
                f"{unit_price:.2f}", f"{line_gross:.2f}", f"{line_net:.2f}",
                f"{line_discount:.2f}", ANCHOR_TS,
            ])

    write_csv(
        seed_path("raw_order_items.csv"),
        ["order_item_id", "order_id", "product_id", "quantity", "unit_price_at_purchase",
         "line_gross_revenue", "line_net_revenue", "line_discount", "_loaded_at"],
        rows,
    )


# ===========================================================================
# raw_returns.csv -- one row per order with status = 'returned'
# ===========================================================================
RETURN_REASONS = ["defective_item", "wrong_size", "not_as_described", "changed_mind",
                   "arrived_late", "duplicate_order", "damaged_in_shipping"]
RESOLUTION_TYPES = ["refund_to_original", "store_credit", "exchange"]


def generate_returns(orders_meta):
    rows = []
    return_id = 0
    for order_id, order_date, customer_id, store_id, status, item_count, discount_amount in orders_meta:
        if status != "returned":
            continue
        return_id += 1
        return_date = order_date + timedelta(days=RNG.randint(3, 21))
        return_reason = RETURN_REASONS[order_id % 7]
        resolution_type = RESOLUTION_TYPES[order_id % 3]
        refund_amount = round(RNG.uniform(15.0, 250.0), 2)
        return_status = "approved" if RNG.randint(1, 100) <= 85 else "denied"

        rows.append([
            return_id, order_id, customer_id, store_id, iso(order_date), iso(return_date),
            return_reason, resolution_type, f"{refund_amount:.2f}", return_status, ANCHOR_TS,
        ])

    write_csv(
        seed_path("raw_returns.csv"),
        ["return_id", "order_id", "customer_id", "store_id", "order_date", "return_date",
         "return_reason", "resolution_type", "refund_amount", "return_status", "_loaded_at"],
        rows,
    )


# ===========================================================================
# raw_ad_spend.csv -- daily spend per campaign, within each campaign's window
# ===========================================================================
CHANNEL_RANGES = {
    "paid_social": {"impressions": (15000, 80000), "clicks": (400, 2500), "attributed_orders": (15, 120)},
    "paid_search": {"impressions": (5000, 25000), "clicks": (200, 1500), "attributed_orders": (20, 150)},
    "email": {"impressions": (8000, 45000), "clicks": (800, 6000), "attributed_orders": (30, 200)},
    "affiliate": {"impressions": (2000, 12000), "clicks": (100, 800), "attributed_orders": (5, 60)},
}


def generate_ad_spend(campaigns):
    rows = []
    spend_id = 0
    for c in campaigns:
        start = date.fromisoformat(c["start_date"])
        end = date.fromisoformat(c["end_date"])
        length_days = (end - start).days + 1
        budget = float(c["budget_usd"])
        channel = c["channel"]
        ranges = CHANNEL_RANGES[channel]

        for day_offset in range(length_days):
            spend_id += 1
            spend_date = start + timedelta(days=day_offset)
            spend_usd = round((budget / length_days) * RNG.uniform(0.75, 1.35), 2)
            impressions = RNG.randint(*ranges["impressions"])
            clicks = RNG.randint(*ranges["clicks"])
            attributed_orders = RNG.randint(*ranges["attributed_orders"])

            rows.append([
                spend_id, c["campaign_id"], c["campaign_name"], channel, c["campaign_type"],
                iso(spend_date), f"{spend_usd:.2f}", impressions, clicks, attributed_orders, ANCHOR_TS,
            ])

    write_csv(
        seed_path("raw_ad_spend.csv"),
        ["spend_id", "campaign_id", "campaign_name", "channel", "campaign_type", "spend_date",
         "spend_usd", "impressions", "clicks", "attributed_orders", "_loaded_at"],
        rows,
    )


# ===========================================================================
# raw_events.csv -- ~500,000 behavioral events, June 2025 through June 2026
# ===========================================================================
EVENT_TYPES = ["page_view", "product_view", "add_to_cart", "checkout_started", "purchase_completed", "page_view"]
EVENT_TRAFFIC = ["paid_search", "paid_social", "organic", "email", "direct"]
DEVICE_WEIGHTS = [(55, "mobile"), (80, "desktop"), (100, "tablet")]
EVENT_PRODUCT_TIER_WEIGHTS = [(60, (1, 20)), (85, (21, 50))]


def event_date_offset(idx100):
    if idx100 < 4:
        return RNG.randint(177, 183)
    if idx100 < 20:
        return RNG.randint(153, 213)
    if idx100 < 28:
        return RNG.randint(214, 244)
    return RNG.randint(0, 379)


def generate_events():
    rows = []
    for i in range(N_EVENTS):
        event_id = i + 1
        idx100 = i % 100
        event_date = ORDER_WINDOW_START + timedelta(days=event_date_offset(idx100))
        customer_id = RNG.randint(1, N_CUSTOMERS)
        event_type = EVENT_TYPES[i % 6]
        traffic_source = EVENT_TRAFFIC[i % 5]
        device_type = weighted_choice(DEVICE_WEIGHTS)

        product_roll = RNG.randint(1, 100)
        if product_roll <= 60:
            product_id = RNG.randint(1, 20)
        elif product_roll <= 85:
            product_id = RNG.randint(21, 50)
        else:
            product_id = ""

        session_id = hashlib.md5(f"{i}session".encode()).hexdigest()

        rows.append([
            event_id, customer_id, iso(event_date), event_type, traffic_source,
            device_type, product_id, session_id, ANCHOR_TS,
        ])

    write_csv(
        seed_path("raw_events.csv"),
        ["event_id", "customer_id", "event_date", "event_type", "traffic_source",
         "device_type", "product_id", "session_id", "_loaded_at"],
        rows,
    )


def main():
    os.makedirs(SEEDS_DIR, exist_ok=True)

    products = read_csv_dicts("catalog_products.csv")
    products_by_id = {int(p["product_id"]): float(p["unit_price"]) for p in products}
    campaigns = read_csv_dicts("catalog_campaigns.csv")

    generate_customers()
    orders_meta = generate_orders()
    generate_order_items(orders_meta, products_by_id)
    generate_returns(orders_meta)
    generate_ad_spend(campaigns)
    generate_events()


if __name__ == "__main__":
    main()
