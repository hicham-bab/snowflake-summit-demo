{{
    config(materialized='ephemeral')
}}

/*
  Materialization: EPHEMERAL
  Computes daily campaign performance by joining ad spend with attributed orders.
  Ephemeral because this intermediate aggregation is only meaningful when
  combined with downstream models like fct_campaign_performance.
*/

WITH ad_spend AS (
    SELECT * FROM {{ ref('stg_marketing__ad_spend') }}
),

orders AS (
    SELECT
        order_date,
        campaign_id,
        COUNT(*)                                        AS total_orders,
        SUM(gross_revenue)                              AS attributed_gross_revenue,
        SUM(net_revenue)                                AS attributed_net_revenue,
        SUM(realized_revenue)                           AS attributed_realized_revenue,
        AVG(gross_revenue)                              AS attributed_aov
    FROM {{ ref('atlas_platform', 'fct_orders') }}
    WHERE campaign_id IS NOT NULL
      AND is_completed
    GROUP BY 1, 2
),

combined AS (
    SELECT
        a.campaign_id,
        a.campaign_name,
        a.channel,
        a.campaign_type,
        a.spend_date,
        a.spend_usd,
        a.impressions,
        a.clicks,
        a.attributed_orders                             AS platform_attributed_orders,
        a.click_through_rate_pct,
        a.cost_per_click,
        a.cost_per_acquisition,

        -- dbt-attributed orders (more accurate — direct order table join)
        COALESCE(o.total_orders, 0)                     AS dbt_attributed_orders,
        COALESCE(o.attributed_gross_revenue, 0)         AS attributed_gross_revenue,
        COALESCE(o.attributed_net_revenue, 0)           AS attributed_net_revenue,
        COALESCE(o.attributed_realized_revenue, 0)      AS attributed_realized_revenue,
        o.attributed_aov,

        -- ROAS: Return on Ad Spend
        CASE
            WHEN a.spend_usd > 0
            THEN ROUND(COALESCE(o.attributed_net_revenue, 0) / a.spend_usd, 2)
            ELSE NULL
        END                                             AS roas,

        a.spend_week,
        a.spend_month,
        a.spend_quarter,
        a.spend_year

    FROM ad_spend a
    LEFT JOIN orders o
        ON  a.campaign_id = o.campaign_id
        AND a.spend_date   = o.order_date
)

SELECT * FROM combined
