{{
    config(materialized='ephemeral')
}}

/*
  Materialization: EPHEMERAL — zero physical footprint.
  Computes per-customer order aggregates that feed dim_customers.
  Ephemeral is ideal here because this is pure enrichment logic
  with no independent analytical value.
*/

WITH customers AS (
    SELECT * FROM {{ ref('stg_ecommerce__customers') }}
),

order_agg AS (
    SELECT
        customer_id,
        COUNT(*)                                                          AS total_orders,
        SUM(CASE WHEN is_completed THEN 1 ELSE 0 END)                     AS completed_orders,
        SUM(CASE WHEN is_returned  THEN 1 ELSE 0 END)                     AS returned_orders,
        SUM(CASE WHEN is_cancelled THEN 1 ELSE 0 END)                     AS cancelled_orders,
        SUM(CASE WHEN is_completed THEN gross_revenue ELSE 0 END)
                                                        AS lifetime_gross_revenue,
        SUM(CASE WHEN is_completed THEN net_revenue   ELSE 0 END)
                                                        AS lifetime_net_revenue,
        AVG(CASE WHEN is_completed THEN gross_revenue END)
                                                        AS avg_order_value,
        MIN(order_date)                                 AS first_order_date,
        MAX(order_date)                                 AS last_order_date,
        DATEDIFF('day', MIN(order_date), MAX(order_date))
                                                        AS days_between_first_last_order,
        COUNT(DISTINCT traffic_source)                  AS distinct_channels_used,
        APPROX_TOP_K(traffic_source, 1)[0]:value::VARCHAR AS most_common_channel
    FROM {{ ref('int_orders_enriched') }}
    GROUP BY 1
)

SELECT
    c.customer_id,
    c.first_name,
    c.last_name,
    c.full_name,
    c.email,
    c.city,
    c.state,
    c.customer_segment,
    c.acquisition_channel,
    c.acquisition_date,
    c.acquisition_month,
    c.acquisition_quarter,
    c.acquisition_year,
    c.age,
    c.gender,
    c.is_email_subscribed,
    c.is_sms_subscribed,
    c.days_since_acquisition,

    -- Order aggregates
    COALESCE(o.total_orders, 0)                         AS total_orders,
    COALESCE(o.completed_orders, 0)                     AS completed_orders,
    COALESCE(o.returned_orders, 0)                      AS returned_orders,
    COALESCE(o.cancelled_orders, 0)                     AS cancelled_orders,
    COALESCE(o.lifetime_gross_revenue, 0)               AS lifetime_gross_revenue,
    COALESCE(o.lifetime_net_revenue, 0)                 AS lifetime_net_revenue,
    o.avg_order_value,
    o.first_order_date,
    o.last_order_date,
    o.days_between_first_last_order,
    COALESCE(o.distinct_channels_used, 0)               AS distinct_channels_used,
    o.most_common_channel,

    -- Customer classification
    CASE
        WHEN o.completed_orders IS NULL         THEN 'never_purchased'
        WHEN o.last_order_date >= DATEADD('day', -90, CURRENT_DATE()) THEN 'active'
        WHEN o.last_order_date >= DATEADD('day', -180, CURRENT_DATE()) THEN 'at_risk'
        ELSE 'churned'
    END                                                 AS customer_lifecycle_stage,

    CASE
        WHEN COALESCE(o.lifetime_net_revenue, 0) >= 1000 THEN 'high_value'
        WHEN COALESCE(o.lifetime_net_revenue, 0) >= 300  THEN 'mid_value'
        WHEN COALESCE(o.lifetime_net_revenue, 0) > 0     THEN 'low_value'
        ELSE 'no_purchases'
    END                                                 AS customer_value_tier

FROM customers c
LEFT JOIN order_agg o ON c.customer_id = o.customer_id
