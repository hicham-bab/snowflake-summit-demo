-- Materialization set in dbt_project.yml: view on Snowflake, Iceberg table in Lake Compute mode.
WITH source AS (
    SELECT * FROM {{ ref('lnd_raw_order_items') }}
),

renamed AS (
    SELECT
        CAST(order_item_id AS BIGINT)                   AS order_item_id,
        CAST(order_id AS BIGINT)                        AS order_id,
        CAST(product_id AS BIGINT)                      AS product_id,
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

        CAST(_loaded_at AS TIMESTAMP)                   AS _loaded_at
    FROM source
)

SELECT * FROM renamed
