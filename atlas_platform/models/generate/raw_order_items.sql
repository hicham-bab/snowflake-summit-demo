{{
    config(
        materialized='table',
        schema='raw',
        tags=['generate', 'raw_data']
    )
}}

/*
  Generates order line items from raw_orders. Each order has 1–5 items.
  Products are weighted toward bestsellers (product_ids 1–20 = 60% of volume).
  Prices are unit_price from dim_products with slight MSRP variation.
*/

WITH order_items_base AS (
    SELECT
        seq4() + 1                                       AS order_item_id,
        o.order_id,
        o.order_date,
        o.status,

        CASE
            WHEN UNIFORM(1, 100, RANDOM()) <= 60 THEN UNIFORM(1, 20, RANDOM())::INT   -- top 20 SKUs: 60%
            WHEN UNIFORM(1, 100, RANDOM()) <= 85 THEN UNIFORM(21, 50, RANDOM())::INT  -- mid tier: 25%
            ELSE                                       UNIFORM(51, 80, RANDOM())::INT  -- long tail: 15%
        END AS product_id,

        UNIFORM(1, 4, RANDOM())::INT AS quantity,

        ROUND(
            p.unit_price * (1 + UNIFORM(-0.05, 0.05, RANDOM())),  -- ±5% price variance
            2
        ) AS unit_price_at_purchase,

        CASE
            WHEN o.discount_amount > 0 THEN
                ROUND(o.discount_amount / o.item_count, 2)
            ELSE 0.00
        END AS line_discount,

        CURRENT_TIMESTAMP() AS _loaded_at

    FROM {{ ref('raw_orders') }} o
    -- Expand each order into its constituent line items
    CROSS JOIN TABLE(GENERATOR(ROWCOUNT => 1))
    JOIN {{ ref('catalog_products') }} p
        ON p.product_id = (
            CASE
                WHEN UNIFORM(1, 100, RANDOM()) <= 60 THEN UNIFORM(1, 20, RANDOM())::INT
                WHEN UNIFORM(1, 100, RANDOM()) <= 85 THEN UNIFORM(21, 50, RANDOM())::INT
                ELSE                                       UNIFORM(51, 80, RANDOM())::INT
            END
        )
)

SELECT
    order_item_id,
    order_id,
    product_id,
    quantity,
    unit_price_at_purchase,
    ROUND(unit_price_at_purchase * quantity, 2)                         AS line_gross_revenue,
    ROUND((unit_price_at_purchase * quantity) - line_discount, 2)       AS line_net_revenue,
    line_discount,
    _loaded_at
FROM order_items_base
