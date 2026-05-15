{{
    config(materialized='ephemeral')
}}

/*
  Materialization: EPHEMERAL
  Aggregates order revenue by calendar day, week, and month.
  Pulled from the platform's fct_orders via dbt Mesh cross-project ref.
*/

WITH orders AS (
    SELECT
        order_id,
        order_date,
        order_month,
        order_quarter,
        order_year,
        store_id,
        store_channel,
        store_region,
        customer_id,
        gross_revenue,
        net_revenue,
        realized_revenue,
        estimated_tax,
        order_level_discount,
        refund_amount,
        is_completed,
        is_returned,
        is_cancelled
    FROM {{ ref('atlas_platform', 'fct_orders') }}
),

daily_agg AS (
    SELECT
        order_date,
        order_month,
        order_quarter,
        order_year,
        store_id,
        store_channel,
        store_region,

        COUNT(*)                                                        AS total_orders,
        SUM(CASE WHEN is_completed THEN 1 ELSE 0 END)                   AS completed_orders,
        SUM(CASE WHEN is_returned  THEN 1 ELSE 0 END)                   AS returned_orders,
        SUM(CASE WHEN is_cancelled THEN 1 ELSE 0 END)                   AS cancelled_orders,

        SUM(CASE WHEN is_completed THEN gross_revenue ELSE 0 END)
                                                        AS gross_revenue,
        SUM(CASE WHEN is_completed THEN net_revenue ELSE 0 END)
                                                        AS net_revenue,
        SUM(CASE WHEN is_completed THEN realized_revenue ELSE 0 END)
                                                        AS realized_revenue,
        SUM(CASE WHEN is_completed THEN estimated_tax ELSE 0 END)
                                                        AS estimated_tax,
        SUM(CASE WHEN is_completed THEN order_level_discount ELSE 0 END)
                                                        AS total_discounts,
        SUM(CASE WHEN is_returned AND refund_amount IS NOT NULL THEN refund_amount ELSE 0 END)
                                                        AS total_refunds,

        COUNT(DISTINCT customer_id)                     AS unique_customers,

        AVG(CASE WHEN is_completed THEN gross_revenue END)
                                                        AS avg_order_value

    FROM orders
    GROUP BY 1, 2, 3, 4, 5, 6, 7
)

SELECT * FROM daily_agg
