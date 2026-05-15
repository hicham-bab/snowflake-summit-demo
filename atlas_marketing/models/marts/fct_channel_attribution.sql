{{
    config(
        materialized='incremental',
        schema='marts_marketing',
        unique_key=['attributed_channel', 'order_month'],
        incremental_strategy='merge',
        cluster_by=['order_month'],
        tags=['mart', 'marketing']
    )
}}

/*
  Materialization: INCREMENTAL (merge on [attributed_channel, order_month]).
  Last-touch channel attribution — monthly rollup of revenue credited to each channel.
*/

WITH touchpoints AS (
    SELECT * FROM {{ ref('int_attribution_touchpoints') }}

    {% if is_incremental() %}
        WHERE order_date > (
            SELECT DATEADD('day', -7, MAX(order_month))
            FROM {{ this }}
        )
    {% endif %}
),

monthly AS (
    SELECT
        attributed_channel,
        DATE_TRUNC('month', order_date)                 AS order_month,
        COUNT(DISTINCT order_id)                        AS attributed_orders,
        SUM(gross_revenue)                              AS attributed_gross_revenue,
        SUM(net_revenue)                                AS attributed_net_revenue,
        SUM(realized_revenue)                           AS attributed_realized_revenue,
        AVG(gross_revenue)                              AS attributed_aov,
        COUNT(DISTINCT customer_id)                     AS unique_customers,

        -- Device split
        SUM(CASE WHEN device_type = 'mobile'  THEN gross_revenue ELSE 0 END)
                                                        AS mobile_revenue,
        SUM(CASE WHEN device_type = 'desktop' THEN gross_revenue ELSE 0 END)
                                                        AS desktop_revenue,
        SUM(CASE WHEN device_type = 'tablet'  THEN gross_revenue ELSE 0 END)
                                                        AS tablet_revenue

    FROM touchpoints
    GROUP BY 1, 2
)

SELECT
    *,
    ROUND(mobile_revenue / NULLIF(attributed_gross_revenue, 0) * 100, 2)
                                                        AS mobile_revenue_pct,
    CURRENT_TIMESTAMP()                                 AS dbt_updated_at
FROM monthly
