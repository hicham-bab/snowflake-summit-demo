{{
    config(materialized='view')
}}

WITH source AS (
    SELECT * FROM {{ source('ecommerce_raw', 'raw_order_items') }}
),

renamed AS (
    SELECT
        order_item_id,
        order_id,
        product_id,
        quantity,
        unit_price_at_purchase,
        line_gross_revenue,
        line_net_revenue,
        line_discount,

        -- Derived
        ROUND(line_gross_revenue - line_net_revenue, 2) AS line_discount_amount,
        CASE
            WHEN line_gross_revenue > 0
            THEN ROUND((line_discount / NULLIF(line_gross_revenue, 0)) * 100, 2)
            ELSE 0
        END                                             AS discount_pct,

        _loaded_at
    FROM source
)

SELECT * FROM renamed
