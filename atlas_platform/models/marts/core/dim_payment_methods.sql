{{
    config(
        materialized='table',
        schema='marts_core',
        tags=['mart', 'core', 'published'],
        access='public'
    )
}}

-- Materialization: TABLE — payment method reference data changes infrequently.
-- Published as a public Mesh node consumed by marketing and finance projects.

SELECT
    payment_method_id,
    payment_method,
    payment_category,
    processor,
    processing_fee_pct,
    supports_refund,
    supports_partial_refund,
    is_active,
    CURRENT_TIMESTAMP()                                 AS dbt_updated_at
FROM {{ ref('catalog_payment_methods') }}
