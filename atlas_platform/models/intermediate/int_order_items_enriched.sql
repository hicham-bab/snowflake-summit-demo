{{
    config(materialized='ephemeral')
}}

/*
  Materialization: EPHEMERAL
  Enriches order items with product metadata for use in fct_order_items.
  Product cost data enables margin calculations at the line-item level.
*/

WITH items AS (
    SELECT * FROM {{ ref('stg_ecommerce__order_items') }}
),

products AS (
    SELECT
        product_id,
        product_name,
        sku,
        category,
        subcategory,
        brand,
        cost_price,
        margin_pct,
        is_featured
    FROM {{ ref('catalog_products') }}
),

enriched AS (
    SELECT
        i.order_item_id,
        i.order_id,
        i.product_id,
        p.product_name,
        p.sku,
        p.category,
        p.subcategory,
        p.brand,
        i.quantity,
        i.unit_price_at_purchase,
        p.cost_price,
        i.line_gross_revenue,
        i.line_net_revenue,
        i.line_discount,
        i.discount_pct,

        -- Margin at purchase price
        ROUND(i.unit_price_at_purchase - p.cost_price, 2)
                                                        AS unit_margin,
        ROUND((i.unit_price_at_purchase - p.cost_price) * i.quantity, 2)
                                                        AS line_margin,
        CASE
            WHEN i.unit_price_at_purchase > 0
            THEN ROUND(
                ((i.unit_price_at_purchase - p.cost_price) / i.unit_price_at_purchase) * 100, 2
            )
            ELSE 0
        END                                             AS line_margin_pct,

        p.is_featured

    FROM items i
    LEFT JOIN products p ON i.product_id = p.product_id
)

SELECT * FROM enriched
