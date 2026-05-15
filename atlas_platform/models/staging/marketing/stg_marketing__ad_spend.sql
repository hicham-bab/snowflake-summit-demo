{{
    config(materialized='view')
}}

WITH source AS (
    SELECT * FROM {{ source('marketing_raw', 'raw_ad_spend') }}
),

renamed AS (
    SELECT
        spend_id,
        campaign_id,
        campaign_name,
        channel,
        campaign_type,
        spend_date,
        spend_usd,
        impressions,
        clicks,
        attributed_orders,

        -- Derived performance metrics
        CASE
            WHEN impressions > 0
            THEN ROUND((clicks::FLOAT / impressions) * 100, 4)
            ELSE 0
        END                                             AS click_through_rate_pct,

        CASE
            WHEN clicks > 0
            THEN ROUND(spend_usd / clicks, 4)
            ELSE NULL
        END                                             AS cost_per_click,

        CASE
            WHEN attributed_orders > 0
            THEN ROUND(spend_usd / attributed_orders, 2)
            ELSE NULL
        END                                             AS cost_per_acquisition,

        DATE_TRUNC('week',  spend_date)                AS spend_week,
        DATE_TRUNC('month', spend_date)                AS spend_month,
        QUARTER(spend_date)                             AS spend_quarter,
        YEAR(spend_date)                               AS spend_year,

        _loaded_at
    FROM source
)

SELECT * FROM renamed
