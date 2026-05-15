{{
    config(
        materialized='table',
        schema='raw',
        tags=['generate', 'raw_data']
    )
}}

/*
  Generates ~500,000 customer behavior events (page views, add-to-cart,
  checkout, purchase) to power funnel analysis and attribution.
  Events precede orders and show drop-off at each funnel stage.
*/

WITH session_base AS (
    SELECT
        seq4() + 1                                          AS event_id,
        UNIFORM(1, 12000, RANDOM())::INT                    AS customer_id,

        DATEADD('day',
            CASE
                WHEN MOD(seq4(), 100) < 4  THEN UNIFORM(177, 183, RANDOM())::INT
                WHEN MOD(seq4(), 100) < 20 THEN UNIFORM(153, 213, RANDOM())::INT
                WHEN MOD(seq4(), 100) < 28 THEN UNIFORM(214, 244, RANDOM())::INT
                ELSE                             UNIFORM(0,   379, RANDOM())::INT
            END,
            '2025-06-01'::DATE
        ) AS event_date,

        CASE (MOD(seq4(), 6))
            WHEN 0 THEN 'page_view'
            WHEN 1 THEN 'product_view'
            WHEN 2 THEN 'add_to_cart'
            WHEN 3 THEN 'checkout_started'
            WHEN 4 THEN 'purchase_completed'
            WHEN 5 THEN 'page_view'   -- weighted extra page_views
        END AS event_type,

        CASE (MOD(seq4(), 5))
            WHEN 0 THEN 'paid_search'
            WHEN 1 THEN 'paid_social'
            WHEN 2 THEN 'organic'
            WHEN 3 THEN 'email'
            WHEN 4 THEN 'direct'
        END AS traffic_source,

        CASE
            WHEN UNIFORM(1, 100, RANDOM()) <= 55 THEN 'mobile'
            WHEN UNIFORM(1, 100, RANDOM()) <= 80 THEN 'desktop'
            ELSE 'tablet'
        END AS device_type,

        CASE
            WHEN UNIFORM(1, 100, RANDOM()) <= 60 THEN UNIFORM(1, 20, RANDOM())::INT
            WHEN UNIFORM(1, 100, RANDOM()) <= 85 THEN UNIFORM(21, 50, RANDOM())::INT
            ELSE NULL
        END AS product_id,

        MD5(CAST(seq4() AS VARCHAR) || 'session') AS session_id,

        CURRENT_TIMESTAMP() AS _loaded_at

    FROM TABLE(GENERATOR(ROWCOUNT => 500000))
)

SELECT *
FROM session_base
WHERE event_date BETWEEN '2025-06-01' AND '2026-06-15'
