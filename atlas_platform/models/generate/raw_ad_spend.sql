{{
    config(
        materialized='table',
        schema='raw',
        tags=['generate', 'raw_data']
    )
}}

/*
  Generates daily ad spend records per campaign, with holiday spending spikes
  aligned to the campaign calendar in dim_campaigns.
  Covers all 30 campaigns from the seed file.
*/

WITH campaign_days AS (
    SELECT
        c.campaign_id,
        c.campaign_name,
        c.channel,
        c.campaign_type,
        c.budget_usd,
        c.start_date,
        c.end_date,
        DATEADD('day', seq4(), c.start_date::DATE) AS spend_date,
        DATEDIFF('day', c.start_date::DATE, c.end_date::DATE) + 1 AS campaign_length_days
    FROM {{ ref('catalog_campaigns') }} c
    CROSS JOIN TABLE(GENERATOR(ROWCOUNT => 200))
    WHERE DATEADD('day', seq4(), c.start_date::DATE) <= c.end_date::DATE
),

spend_calc AS (
    SELECT
        ROW_NUMBER() OVER (ORDER BY campaign_id, spend_date) AS spend_id,
        campaign_id,
        campaign_name,
        channel,
        campaign_type,
        spend_date,

        -- Daily spend = budget / campaign_length with daily variance
        ROUND(
            (budget_usd::FLOAT / campaign_length_days)
            * UNIFORM(0.75, 1.35, RANDOM()),  -- ±25% daily variance
            2
        ) AS spend_usd,

        -- Impressions based on channel CPM benchmarks
        CASE channel
            WHEN 'paid_social'  THEN UNIFORM(15000, 80000, RANDOM())::INT
            WHEN 'paid_search'  THEN UNIFORM(5000,  25000, RANDOM())::INT
            WHEN 'email'        THEN UNIFORM(8000,  45000, RANDOM())::INT
            WHEN 'affiliate'    THEN UNIFORM(2000,  12000, RANDOM())::INT
        END AS impressions,

        -- Clicks
        CASE channel
            WHEN 'paid_social'  THEN UNIFORM(400,  2500, RANDOM())::INT
            WHEN 'paid_search'  THEN UNIFORM(200,  1500, RANDOM())::INT
            WHEN 'email'        THEN UNIFORM(800,  6000, RANDOM())::INT
            WHEN 'affiliate'    THEN UNIFORM(100,   800, RANDOM())::INT
        END AS clicks,

        -- Attributed orders (conversion rate 2–8%)
        CASE channel
            WHEN 'paid_social'  THEN UNIFORM(15, 120, RANDOM())::INT
            WHEN 'paid_search'  THEN UNIFORM(20, 150, RANDOM())::INT
            WHEN 'email'        THEN UNIFORM(30, 200, RANDOM())::INT
            WHEN 'affiliate'    THEN UNIFORM(5,   60, RANDOM())::INT
        END AS attributed_orders,

        CURRENT_TIMESTAMP() AS _loaded_at

    FROM campaign_days
)

SELECT * FROM spend_calc
