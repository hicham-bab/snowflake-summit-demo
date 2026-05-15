{{
    config(materialized='view')
}}

/*
  Marketing project's local reference to campaign metadata.
  Campaign info is embedded in raw_ad_spend at generation time,
  so this derives campaign attributes from the spend source itself.
  Avoids a cross-project dep on the platform's private staging models.
*/

SELECT DISTINCT
    campaign_id,
    campaign_name,
    channel,
    campaign_type,
    MIN(spend_date) OVER (PARTITION BY campaign_id) AS start_date,
    MAX(spend_date) OVER (PARTITION BY campaign_id) AS end_date,
    SUM(spend_usd)  OVER (PARTITION BY campaign_id) AS budget_usd,
    DATE_TRUNC('month', MIN(spend_date) OVER (PARTITION BY campaign_id))
                                                    AS campaign_start_month,
    QUARTER(MIN(spend_date) OVER (PARTITION BY campaign_id))
                                                    AS campaign_quarter,
    YEAR(MIN(spend_date) OVER (PARTITION BY campaign_id))
                                                    AS campaign_year

FROM {{ ref('stg_marketing__ad_spend') }}
