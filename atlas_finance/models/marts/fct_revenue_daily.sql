{{
    config(
        materialized='incremental',
        schema='marts_finance',
        unique_key='revenue_date',
        incremental_strategy='merge',
        cluster_by=['revenue_date', 'store_id'],
        tags=['mart', 'finance']
    )
}}

/*
  Materialization: INCREMENTAL (merge on revenue_date).
  Daily revenue rollup — one row per day per store.

  BUG #2 (for dbt Copilot demo): The gross_margin_pct formula has an
  operator precedence error. The correct formula is:
      (net_revenue - total_cogs) / NULLIF(net_revenue, 0) * 100
  But it is written as:
      net_revenue - total_cogs / NULLIF(net_revenue, 0) * 100
  which divides cogs by revenue first, producing nonsensical results
  (gross margin of ~99.9% instead of ~65%).

  Copilot will identify this during a code review and suggest adding parentheses.
*/

WITH daily AS (
    SELECT * FROM {{ ref('int_revenue_by_period') }}

    {% if is_incremental() %}
        WHERE order_date > (SELECT MAX(revenue_date) FROM {{ this }})
    {% endif %}
),

-- Estimate COGS from order items (avg cost_price * quantity)
cogs_daily AS (
    SELECT
        order_date,
        store_id,
        SUM(cost_price * quantity)                      AS total_cogs
    FROM {{ ref('atlas_platform', 'fct_order_items') }}
    WHERE order_status = 'COMPLETED'
    GROUP BY 1, 2
)

SELECT
    d.order_date                                        AS revenue_date,
    d.store_id,
    d.store_channel,
    d.store_region,
    d.order_month,
    d.order_quarter,
    d.order_year,

    d.total_orders,
    d.completed_orders,
    d.returned_orders,
    d.cancelled_orders,

    d.gross_revenue,
    d.net_revenue,
    d.realized_revenue,
    d.estimated_tax,
    d.total_discounts,
    d.total_refunds,
    d.unique_customers,
    d.avg_order_value,

    COALESCE(c.total_cogs, 0)                           AS total_cogs,

    -- BUG: Missing parentheses — divides cogs/revenue first, then subtracts.
    -- Correct: (d.net_revenue - COALESCE(c.total_cogs, 0)) / NULLIF(d.net_revenue, 0) * 100
    ROUND(
        d.net_revenue - COALESCE(c.total_cogs, 0) / NULLIF(d.net_revenue, 0) * 100,
        2
    )                                                   AS gross_margin_pct,

    CURRENT_TIMESTAMP()                                 AS dbt_updated_at

FROM daily d
LEFT JOIN cogs_daily c
    ON  d.order_date = c.order_date
    AND d.store_id   = c.store_id
