{{
    config(
        materialized='table',
        schema='marts_finance',
        tags=['mart', 'finance']
    )
}}

/*
  Materialization: TABLE — LTV is computed on all customers (12K rows),
  a full refresh ensures consistent results without incremental complexity.
*/

WITH customers AS (
    SELECT
        customer_id,
        full_name,
        customer_segment,
        customer_value_tier,
        acquisition_channel,
        acquisition_date,
        acquisition_month,
        first_order_date,
        last_order_date,
        total_orders,
        completed_orders,
        lifetime_gross_revenue,
        lifetime_net_revenue,
        avg_order_value,
        customer_lifecycle_stage,
        days_since_acquisition
    FROM {{ ref('atlas_platform', 'dim_customers') }}
),

refund_totals AS (
    SELECT
        customer_id,
        SUM(refund_amount)                              AS total_refunds
    FROM {{ ref('int_refunds_enriched') }}
    GROUP BY 1
)

SELECT
    c.customer_id,
    c.full_name,
    c.customer_segment,
    c.customer_value_tier,
    c.acquisition_channel,
    c.acquisition_date,
    c.acquisition_month,
    c.first_order_date,
    c.last_order_date,
    c.total_orders,
    c.completed_orders,
    c.lifetime_gross_revenue,
    c.lifetime_net_revenue,
    COALESCE(r.total_refunds, 0)                        AS total_refunds,

    -- Net LTV = lifetime net revenue minus refunds
    c.lifetime_net_revenue - COALESCE(r.total_refunds, 0)
                                                        AS net_ltv,

    c.avg_order_value,
    c.customer_lifecycle_stage,
    c.days_since_acquisition,

    -- Predicted 12-month LTV (simple extrapolation: avg_order_value × purchase_frequency)
    CASE
        WHEN c.days_since_acquisition > 0 AND c.total_orders > 0
        THEN ROUND(
            c.avg_order_value
            * (c.total_orders::FLOAT / NULLIF(c.days_since_acquisition, 0) * 365),
            2
        )
        ELSE 0
    END                                                 AS predicted_12m_ltv,

    CURRENT_TIMESTAMP()                                 AS dbt_updated_at

FROM customers c
LEFT JOIN refund_totals r ON c.customer_id = r.customer_id
