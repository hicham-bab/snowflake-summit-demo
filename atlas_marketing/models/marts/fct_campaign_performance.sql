{{
    config(
        materialized='incremental',
        schema='marts_marketing',
        unique_key=['campaign_id', 'spend_date'],
        incremental_strategy='merge',
        cluster_by=['spend_month', 'channel'],
        tags=['mart', 'marketing']
    )
}}

/*
  Materialization: INCREMENTAL (merge on [campaign_id, spend_date]).
  Daily campaign performance rollup — one row per campaign per day.
  Clustered by spend_month + channel for efficient time-slice queries.

  BUG #4 (for dbt Copilot demo): This model has no description in the YAML.
  Copilot will flag the missing documentation and generate a description + column docs.
*/

WITH daily AS (
    SELECT * FROM {{ ref('int_campaign_daily_metrics') }}

    {% if is_incremental() %}
        WHERE spend_date > (SELECT MAX(spend_date) FROM {{ this }})
    {% endif %}
)

SELECT
    campaign_id,
    campaign_name,
    channel,
    campaign_type,
    spend_date,
    spend_week,
    spend_month,
    spend_quarter,
    spend_year,
    spend_usd,
    impressions,
    clicks,
    platform_attributed_orders,
    dbt_attributed_orders,
    attributed_gross_revenue,
    attributed_net_revenue,
    attributed_realized_revenue,
    attributed_aov,
    click_through_rate_pct,
    cost_per_click,
    cost_per_acquisition,
    roas,

    -- Efficiency tier
    CASE
        WHEN roas >= 5.0 THEN 'high_performing'
        WHEN roas >= 2.5 THEN 'efficient'
        WHEN roas >= 1.0 THEN 'break_even'
        ELSE 'underperforming'
    END                                                 AS roas_tier,

    CURRENT_TIMESTAMP()                                 AS dbt_updated_at

FROM daily
