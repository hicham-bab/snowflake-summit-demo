{{
    config(
        materialized='table',
        schema='marts_finance',
        tags=['mart', 'finance']
    )
}}

/*
  Materialization: TABLE — monthly revenue is small enough (12–18 rows)
  that a full rebuild is simpler and more reliable than incremental.
  This is the exec-reporting table used for board-level revenue metrics.
*/

WITH daily AS (
    SELECT * FROM {{ ref('fct_revenue_daily') }}
),

monthly AS (
    SELECT
        order_month                                     AS revenue_month,
        order_quarter,
        order_year,
        store_channel,
        store_region,

        SUM(total_orders)                               AS total_orders,
        SUM(completed_orders)                           AS completed_orders,
        SUM(returned_orders)                            AS returned_orders,

        SUM(gross_revenue)                              AS gross_revenue,
        SUM(net_revenue)                                AS net_revenue,
        SUM(realized_revenue)                           AS realized_revenue,
        SUM(total_discounts)                            AS total_discounts,
        SUM(total_refunds)                              AS total_refunds,
        SUM(total_cogs)                                 AS total_cogs,
        SUM(estimated_tax)                              AS estimated_tax,
        SUM(unique_customers)                           AS unique_customers,
        AVG(avg_order_value)                            AS avg_order_value,

        -- Correct gross margin at the monthly level
        ROUND(
            (SUM(net_revenue) - SUM(total_cogs))
            / NULLIF(SUM(net_revenue), 0) * 100,
            2
        )                                               AS gross_margin_pct,

        -- Month-over-month change (LAG requires table — cannot use in ephemeral)
        LAG(SUM(net_revenue), 1) OVER (
            PARTITION BY store_channel
            ORDER BY order_month
        )                                               AS prior_month_net_revenue

    FROM daily
    GROUP BY 1, 2, 3, 4, 5
)

SELECT
    *,
    ROUND(
        (net_revenue - COALESCE(prior_month_net_revenue, net_revenue))
        / NULLIF(prior_month_net_revenue, 0) * 100,
        2
    )                                                   AS mom_revenue_growth_pct,

    CURRENT_TIMESTAMP()                                 AS dbt_updated_at

FROM monthly
