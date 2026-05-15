{{
    config(materialized='view')
}}

/*
  Marketing project's staging view over raw_ad_spend.
  raw_ad_spend already contains campaign_name and channel from generation time,
  so no join to dim_campaigns is needed here.
*/

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
        click_through_rate_pct,
        cost_per_click,
        cost_per_acquisition,

        DATE_TRUNC('week',  spend_date)                AS spend_week,
        DATE_TRUNC('month', spend_date)                AS spend_month,
        QUARTER(spend_date)                            AS spend_quarter,
        YEAR(spend_date)                               AS spend_year,

        _loaded_at
    FROM source
)

SELECT * FROM renamed
