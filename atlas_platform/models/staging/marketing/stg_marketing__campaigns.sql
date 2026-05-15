{{
    config(materialized='view')
}}

-- Staging view over the dim_campaigns seed — adds derived fields for downstream use.

WITH campaigns AS (
    SELECT * FROM {{ ref('catalog_campaigns') }}
),

renamed AS (
    SELECT
        campaign_id,
        campaign_name,
        channel,
        campaign_type,
        start_date,
        end_date,
        budget_usd,
        target_segment,
        utm_source,
        utm_medium,
        utm_campaign,
        is_active,

        -- Derived
        DATEDIFF('day', start_date, end_date) + 1      AS campaign_duration_days,
        ROUND(budget_usd / NULLIF(DATEDIFF('day', start_date, end_date) + 1, 0), 2)
                                                        AS daily_budget_usd,
        DATE_TRUNC('month', start_date)                AS campaign_start_month,
        QUARTER(start_date)                             AS campaign_quarter,
        YEAR(start_date)                               AS campaign_year

    FROM campaigns
)

SELECT * FROM renamed
