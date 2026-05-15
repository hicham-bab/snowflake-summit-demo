{{
    config(
        materialized='table',
        schema='marts_core',
        tags=['mart', 'core', 'published'],
        access='public'
    )
}}

-- Materialization: TABLE — store roster is stable; full refresh is appropriate.

SELECT
    store_id,
    store_name,
    store_type,
    channel,
    city,
    state,
    region,
    opened_date,
    sq_footage,
    district,
    is_active,
    manager_name,
    CURRENT_TIMESTAMP()                                 AS dbt_updated_at
FROM {{ ref('catalog_stores') }}
