# Atlas Commerce — Snowflake Summit Demo Script

5-act narrative: Setup → dbt Mesh → Materializations → Semantic Layer → Copilot fixes

---

## Act 1 — The Architecture (2 min)

**Talking point:** "Atlas Commerce is an omnichannel retailer — 19 physical stores, online, and mobile. Their data team runs three dbt projects connected via dbt Mesh."

Open the dbt Cloud lineage graph and show:
- `atlas_platform` as the producer — dims + facts published as public nodes
- `atlas_marketing` consuming `fct_orders` for attribution
- `atlas_finance` consuming `fct_orders` + `fct_order_items` for P&L

**Key message:** Each team owns their domain. Finance can't accidentally break marketing's models. The platform team publishes a contract — and consumers depend on that contract, not on internal implementation details.

---

## Act 2 — dbt Mesh in action (3 min)

Show `atlas_marketing/models/intermediate/int_campaign_daily_metrics.sql`:

```sql
FROM {{ ref('atlas_platform', 'fct_orders') }}
```

**Talking point:** "This cross-project ref is a first-class dbt concept. If the platform team renames or removes `fct_orders`, dbt will fail the marketing project's build — not silently break their reports. Contracts are enforced at compile time."

Show `_core__models.yml`:
```yaml
- name: fct_orders
  group: core_platform
  access: public
```

**Key message:** Public models are the API surface of your data platform. Everything else is private — hidden complexity that only the platform team needs to manage.

---

## Act 3 — All 5 materializations (4 min)

Walk through the DAG and call out each materialization:

| Stop | Model | Materialization | Why it matters |
|---|---|---|---|
| 1 | `stg_ecommerce__orders` | **view** | Always fresh, zero storage — perfect for staging |
| 2 | `int_orders_enriched` | **ephemeral** | Click "Compile" to show the inlined CTE in `fct_orders` — zero physical footprint |
| 3 | `dim_customers` | **table** | Full rebuild — 12K rows, cheap, always consistent |
| 4 | `fct_orders` | **incremental** | 300K rows — only processes new orders each run (show the `{% if is_incremental() %}` block) |
| 5 | `scd_customers` | **snapshot** | SCD Type 2 — run `dbt snapshot` to see `dbt_valid_from` / `dbt_valid_to` track segment changes over time |

**Demo the incremental:** Run `dbt run --select fct_orders` twice:
- First run: processes all 300K rows (cold start)
- Second run: processes 0 rows (nothing new since last `_loaded_at`)

**Key message:** dbt gives you the right tool for each table. You don't write merge statements by hand — you declare the strategy and dbt handles the SQL.

---

## Act 4 — Semantic Layer + Snowflake Semantic Views (4 min)

### Part A — dbt Semantic Layer (MetricFlow)

Open dbt Cloud Explore and run:

**Query 1 — Revenue by channel:**
```
metrics: [total_net_revenue, average_order_value, return_rate]
group_by: [store_channel, order_month]
filter: order_date >= '2025-11-01' AND order_date <= '2025-12-31'
```
Show the holiday spike: online + mobile outperform in-store in November.

**Query 2 — Campaign ROAS:**
```
metrics: [total_marketing_spend, blended_roas, cost_per_order]
group_by: [channel, spend_month]
```
Show paid search has higher ROAS than paid social. Cyber Monday spike visible.

**Key message:** "The same metric definition is used everywhere — in Tableau, Sigma, the dbt Cloud API. No more 'which revenue number is right?' because there's only one definition."

### Part B — Snowflake Semantic Views + Cortex Analyst

Switch to a Snowflake worksheet and open Cortex Analyst against `REVENUE_SEMANTIC_VIEW`.

Ask natural language:
1. *"What was our total revenue by region in Q4 2025?"*
2. *"Which day had the highest average order value?"*
3. *"Show return rate by channel for November and December 2025"*

**Key message:** "The semantic view tells Cortex Analyst what each column means — 'realized_revenue' is cash collected, not gross, 'store_channel' means in-store vs. online. This context is why the SQL it generates is actually correct."

**Contrast:** Without the semantic view, Cortex would guess. With it, it knows Atlas's domain — same as how a trained analyst thinks about the data.

---

## Act 5 — dbt Copilot fixes (3 min)

Walk through each intentional bug and show Copilot diagnosing + fixing it.

### Bug 1 — Broken ref (compile error)
Navigate to `atlas_marketing/models/marts/fct_customer_acquisition.sql`.

Run `dbt compile --select fct_customer_acquisition`. Show the error:
```
Compilation Error: node 'ref('stg_marketing__leads')' was not found
```

Ask dbt Copilot: *"Why is fct_customer_acquisition failing to compile?"*

Copilot response: identifies the missing model, suggests either creating `stg_marketing__leads` or removing the join if leads data isn't yet available.

**Fix:** Remove the `leads` CTE and join.

### Bug 2 — Wrong metric formula (operator precedence)
Open `atlas_finance/models/marts/fct_revenue_daily.sql`, line ~80:

```sql
-- Current (wrong):
d.net_revenue - COALESCE(c.total_cogs, 0) / NULLIF(d.net_revenue, 0) * 100

-- Ask Copilot: "Review gross_margin_pct — does this formula look right?"
-- Copilot identifies the missing parentheses:
(d.net_revenue - COALESCE(c.total_cogs, 0)) / NULLIF(d.net_revenue, 0) * 100
```

**Key message:** Copilot catches the kind of bug that passes linting and even unit tests — it understands business intent, not just syntax.

### Bug 3 — Missing data quality tests
Open `atlas_platform/models/marts/core/_core__models.yml`.

Show `dim_customers.customer_id` has no tests (the commented-out block).

Ask Copilot: *"Generate full test coverage for dim_customers."*

Copilot adds `unique`, `not_null`, and `relationships` tests for all key columns.

### Bug 4 — Missing documentation
Show `fct_campaign_performance` has no model `description` in `_marketing__models.yml`.

Ask Copilot: *"Write documentation for fct_campaign_performance including column descriptions."*

**Key message:** Copilot in context — it already knows what the model does from the SQL. Documentation generation goes from hours to seconds.

---

## Wrap-up talking points

- **dbt Mesh** → organizational scalability without coupling
- **Materializations** → right tool for each table, declared not scripted
- **Semantic Layer** → one metric definition used everywhere
- **Snowflake Semantic Views** → Cortex Analyst understands your business, not just your columns
- **dbt Copilot** → catches what code review misses: logic bugs, test gaps, stale docs
