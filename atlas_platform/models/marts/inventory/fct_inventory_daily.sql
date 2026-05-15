{{
    config(
        materialized='incremental',
        schema='marts_inventory',
        unique_key=['product_id', 'store_id', 'snapshot_date'],
        incremental_strategy='merge',
        cluster_by=['snapshot_date', 'product_id'],
        tags=['mart', 'inventory']
    )
}}

/*
  Materialization: INCREMENTAL (merge on composite key).
  Generates a synthetic daily inventory position per product per store.
  In a real implementation this would read from an inventory management source.

  Demonstrates: composite unique_key incremental merge on Snowflake.
*/

WITH product_store_spine AS (
    SELECT
        p.product_id,
        p.product_name,
        p.category,
        p.cost_price,
        s.store_id,
        s.store_name,
        s.store_type,
        s.region
    FROM {{ ref('catalog_products') }} p
    CROSS JOIN {{ ref('catalog_stores') }} s
    WHERE s.is_active
),

date_series AS (
    SELECT date_day AS snapshot_date
    FROM {{ ref('dim_dates') }}
    WHERE date_day BETWEEN '2025-06-01' AND CURRENT_DATE()

    {% if is_incremental() %}
        AND date_day > (SELECT MAX(snapshot_date) FROM {{ this }})
    {% endif %}
),

inventory AS (
    SELECT
        ps.product_id,
        ps.product_name,
        ps.category,
        ps.cost_price,
        ps.store_id,
        ps.store_name,
        ps.store_type,
        ps.region,
        d.snapshot_date,

        -- Synthetic units on hand (physical stores 50–500, digital unbounded)
        CASE
            WHEN ps.store_type = 'physical'
            THEN UNIFORM(20, 450, RANDOM())::INT
            ELSE UNIFORM(500, 5000, RANDOM())::INT
        END AS units_on_hand,

        -- Units sold that day (pulled from order items in a real implementation)
        UNIFORM(0, 25, RANDOM())::INT AS units_sold_today,

        -- Reorder flag: <30 units for physical, <200 for digital
        CASE
            WHEN ps.store_type = 'physical' AND UNIFORM(20, 450, RANDOM()) < 30  THEN TRUE
            WHEN ps.store_type = 'digital'  AND UNIFORM(500, 5000, RANDOM()) < 200 THEN TRUE
            ELSE FALSE
        END AS is_below_reorder_point,

        CURRENT_TIMESTAMP() AS dbt_updated_at

    FROM product_store_spine ps
    CROSS JOIN date_series d
)

SELECT * FROM inventory
