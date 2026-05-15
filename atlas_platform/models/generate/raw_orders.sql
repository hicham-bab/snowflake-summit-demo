{{
    config(
        materialized='table',
        schema='raw',
        tags=['generate', 'raw_data']
    )
}}

/*
  Generates ~300,000 orders from June 2025 through June 2026.
  Uses MOD(seq4(), 100) to create realistic seasonality buckets:
    - 4%  → BFCM window (Nov 25–Dec 1)
    - 16% → Holiday season (Nov–Dec)
    - 8%  → January slowdown
    - 7%  → February–April spring ramp
    - 65% → Rest of year (distributed across full 380-day range)
  Run via: dbt run --select tag:generate
*/

WITH order_base AS (
    SELECT
        seq4() + 1 AS order_id,

        DATEADD('day',
            CASE
                WHEN MOD(seq4(), 100) < 4  THEN UNIFORM(177, 183, RANDOM())  -- BFCM (4%)
                WHEN MOD(seq4(), 100) < 20 THEN UNIFORM(153, 213, RANDOM())  -- Holiday (16%)
                WHEN MOD(seq4(), 100) < 28 THEN UNIFORM(214, 244, RANDOM())  -- Jan slowdown (8%)
                WHEN MOD(seq4(), 100) < 35 THEN UNIFORM(244, 319, RANDOM())  -- Feb–Apr (7%)
                ELSE                             UNIFORM(0,   379, RANDOM())  -- Baseline (65%)
            END::INT,
            '2025-06-01'::DATE
        ) AS order_date,

        UNIFORM(1, 12000, RANDOM())::INT AS customer_id,

        CASE
            WHEN UNIFORM(1, 100, RANDOM()) <= 38 THEN 20   -- online
            WHEN UNIFORM(1, 100, RANDOM()) <= 55 THEN 21   -- mobile app
            ELSE UNIFORM(1, 19, RANDOM())::INT              -- physical store
        END AS store_id,

        CASE
            WHEN MOD(seq4(), 100) < 8  THEN 'cancelled'
            WHEN MOD(seq4(), 100) < 15 THEN 'returned'
            ELSE                            'completed'
        END AS status,

        -- Discount: 22% of orders have a discount
        CASE
            WHEN MOD(seq4(), 100) < 22 THEN ROUND(UNIFORM(5.0, 30.0, RANDOM()), 2)
            ELSE 0.00
        END AS discount_amount,

        CASE
            WHEN UNIFORM(1, 100, RANDOM()) <= 52 THEN 'credit_card'
            WHEN UNIFORM(1, 100, RANDOM()) <= 75 THEN 'debit_card'
            WHEN UNIFORM(1, 100, RANDOM()) <= 88 THEN 'paypal'
            WHEN UNIFORM(1, 100, RANDOM()) <= 95 THEN 'apple_pay'
            ELSE 'google_pay'
        END AS payment_method,

        -- 32% of orders are campaign-attributed
        CASE
            WHEN MOD(seq4(), 100) < 32 THEN UNIFORM(1, 30, RANDOM())::INT
            ELSE NULL
        END AS campaign_id,

        CASE
            WHEN UNIFORM(1, 100, RANDOM()) <= 22 THEN 'paid_search'
            WHEN UNIFORM(1, 100, RANDOM()) <= 42 THEN 'paid_social'
            WHEN UNIFORM(1, 100, RANDOM()) <= 58 THEN 'organic'
            WHEN UNIFORM(1, 100, RANDOM()) <= 70 THEN 'email'
            WHEN UNIFORM(1, 100, RANDOM()) <= 82 THEN 'direct'
            WHEN UNIFORM(1, 100, RANDOM()) <= 90 THEN 'affiliate'
            ELSE 'referral'
        END AS traffic_source,

        UNIFORM(1, 5, RANDOM())::INT AS item_count,

        CURRENT_TIMESTAMP() AS _loaded_at

    FROM TABLE(GENERATOR(ROWCOUNT => 300000))
)

SELECT
    order_id,
    order_date,
    customer_id,
    store_id,
    status,
    discount_amount,
    payment_method,
    campaign_id,
    traffic_source,
    item_count,
    DATEADD('minute', UNIFORM(0, 1380, RANDOM()), order_date::TIMESTAMP) AS ordered_at,
    _loaded_at
FROM order_base
-- Filter to valid date range
WHERE order_date BETWEEN '2025-06-01' AND '2026-06-15'
