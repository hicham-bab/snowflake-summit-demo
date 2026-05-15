# Atlas Commerce — dbt + Snowflake Summit Demo

A production-grade dbt Fusion project for Snowflake Summit, showcasing:

- **dbt Mesh** — 3 interconnected projects (platform → marketing, platform → finance)
- **All 5 dbt materializations** — table, view, ephemeral, incremental, snapshot
- **dbt Semantic Layer** — MetricFlow metrics across all three projects
- **Snowflake Semantic Views** — native Snowflake AI context for Cortex Analyst
- **Intentional issues** — pre-loaded bugs for dbt Copilot live demo
- **Realistic data** — ~300K orders, June 2025 – June 2026, with holiday seasonality

## Project structure

```
snowflake-summit-demo/
├── atlas_platform/      ← Producer (core data platform)
├── atlas_marketing/     ← Consumer #1 (campaign analytics, attribution)
├── atlas_finance/       ← Consumer #2 (revenue, P&L, cohorts, LTV)
├── snowflake_semantic_views/  ← Native Snowflake semantic context for Cortex
└── setup/                  ← Snowflake DDL (warehouses, roles, grants)
```

## Quick start

### 1. Snowflake setup

```sql
-- Run as ACCOUNTADMIN in a Snowflake worksheet
-- Copies to clipboard: setup/01_snowflake_setup.sql
```

### 2. Configure credentials

```bash
cp .env.example .env
# Edit .env with your SNOWFLAKE_ACCOUNT, SNOWFLAKE_USER, SNOWFLAKE_PASSWORD
source .env
```

### 3. Install dbt packages and generate raw data

```bash
# Platform project first
cd atlas_platform
dbt deps
dbt seed                              # loads products, stores, campaigns CSVs
dbt run --select tag:generate         # creates ~300K synthetic orders (use LARGE WH)
dbt run --exclude tag:generate        # builds all staging, intermediate, and mart models
dbt snapshot                          # captures initial customer SCD snapshot
dbt test

# Marketing consumer
cd ../atlas_marketing
dbt deps
dbt run
dbt test

# Finance consumer
cd ../atlas_finance
dbt deps
dbt run
dbt test
```

### 4. Register Snowflake Semantic Views

```sql
-- Run each file in order in a Snowflake worksheet
-- snowflake_semantic_views/01_revenue_semantic_view.sql
-- snowflake_semantic_views/02_customer_semantic_view.sql
-- snowflake_semantic_views/03_marketing_semantic_view.sql
```

## Data volume

| Table | Rows | Materialization |
|---|---|---|
| `raw_customers` | 12,000 | Table (generate) |
| `raw_orders` | ~300,000 | Table (generate) |
| `raw_order_items` | ~750,000 | Table (generate) |
| `raw_events` | ~500,000 | Table (generate) |
| `raw_ad_spend` | ~2,400 | Table (generate) |
| `dim_customers` | 12,000 | Table |
| `fct_orders` | ~300,000 | Incremental (merge) |
| `fct_order_items` | ~750,000 | Incremental (merge) |
| `fct_inventory_daily` | ~1.8M | Incremental (composite key) |
| `scd_customers` | 12,000+ | Snapshot (SCD Type 2) |

## Materialization showcase

| Materialization | Where | Why |
|---|---|---|
| **view** | All staging models | Zero storage cost, always fresh |
| **table** | dims, fct_revenue_monthly, fct_customer_ltv | Full rebuild OK — small rowcount or infrequent change |
| **ephemeral** | All `int_*` models | Pure logic encapsulation, no physical footprint |
| **incremental** | fct_orders, fct_order_items, fct_revenue_daily, fct_campaign_performance | High cardinality, append/merge by date window |
| **snapshot** | scd_customers | SCD Type 2 — track customer segment + lifecycle changes over time |

## Intentional bugs for dbt Copilot demo

| # | Location | Bug | Copilot action |
|---|---|---|---|
| 1 | `atlas_marketing/models/marts/fct_customer_acquisition.sql` | `ref('stg_marketing__leads')` — model does not exist | Diagnose compilation error, suggest fix |
| 2 | `atlas_finance/models/marts/fct_revenue_daily.sql` | Operator precedence error in `gross_margin_pct` formula | Code review → identify missing parentheses |
| 3 | `atlas_platform/models/marts/core/_core__models.yml` | `dim_customers.customer_id` missing `unique` + `not_null` tests | Documentation review → generate test coverage |
| 4 | `atlas_marketing/models/marts/_marketing__models.yml` | `fct_campaign_performance` has no model description | Documentation review → generate description |
| 5 | `atlas_platform/models/staging/ecommerce/_ecommerce__sources.yml` | `raw_orders` source missing `loaded_at_field` + `freshness` | Observability review → add freshness config |

## dbt Mesh architecture

```
atlas_platform (producer)
├── PUBLIC: dim_customers, dim_products, dim_stores, dim_dates
├── PUBLIC: fct_orders, fct_order_items
└── Exposes via: group: core_platform, access: public

atlas_marketing (consumer)
├── cross-project ref: {{ ref('atlas_platform', 'fct_orders') }}
├── cross-project ref: {{ ref('atlas_platform', 'dim_customers') }}
└── Produces: campaign performance, attribution, channel metrics

atlas_finance (consumer)
├── cross-project ref: {{ ref('atlas_platform', 'fct_orders') }}
├── cross-project ref: {{ ref('atlas_platform', 'fct_order_items') }}
├── cross-project ref: {{ ref('atlas_platform', 'dim_customers') }}
└── Produces: revenue P&L, LTV, cohort retention
```

## Semantic Layer demo queries

Use the dbt Semantic Layer API or dbt Cloud Explore to run:

```
# Revenue by channel, last 3 months
metrics: [total_net_revenue, average_order_value]
group_by: [store_channel, order_month]

# Campaign ROAS comparison
metrics: [total_marketing_spend, blended_roas, cost_per_order]
group_by: [channel, spend_month]

# Customer retention cohorts
metrics: [cohort_month_1_retention, total_cohort_revenue]
group_by: [cohort_month, acquisition_channel]
```

## Snowflake Cortex Analyst questions to demo

After registering the semantic views, paste these into Cortex Analyst:

- *"What was our total revenue in Q4 2025 compared to Q4 2024?"*
- *"Which region had the highest average order value last month?"*
- *"Show me return rate by channel over the past 6 months"*
- *"Which campaign had the best ROAS in November 2025?"*
- *"How many active customers do we have in the Premium segment?"*
