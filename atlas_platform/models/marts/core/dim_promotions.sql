{{
    config(
        materialized='table',
        schema='marts_core',
        tags=['mart', 'core', 'published'],
        access='public'
    )
}}

-- Materialization: TABLE — promotion catalog changes infrequently.
-- Published as a public Mesh node consumed by marketing and finance projects.

SELECT
    promotion_id,
    promotion_code,
    promotion_name,
    discount_type,
    discount_value,
    min_order_amount,
    start_date,
    end_date,
    channel,
    is_stackable,
    max_redemptions,
    is_active,
    CURRENT_TIMESTAMP()                                 AS dbt_updated_at
FROM {{ ref('catalog_promotions') }}
