{{
    config(
        materialized='incremental',
        schema='marts_core',
        unique_key='order_item_id',
        incremental_strategy='merge',
        cluster_by=['order_id', 'category'],
        tags=['mart', 'core', 'published'],
        access='public'
    )
}}

/*
  Materialization: INCREMENTAL (merge strategy).
  Line-item fact table — high cardinality (~750K rows). Incremental merge
  avoids full reprocessing on every run. Clustered by order_id + category
  for efficient joins and category-level aggregations in Snowflake.
*/

WITH items AS (
    SELECT * FROM {{ ref('int_order_items_enriched') }}
),

orders AS (
    SELECT order_id, order_date, customer_id, store_id, order_status,
           store_channel, traffic_source, campaign_id, order_month, order_year
    FROM {{ ref('fct_orders') }}

    {% if is_incremental() %}
        WHERE dbt_updated_at >= (
            SELECT DATEADD('day', -3, MAX(dbt_updated_at))
            FROM {{ this }}
        )
    {% endif %}
),

joined AS (
    SELECT
        i.order_item_id,
        i.order_id,
        o.order_date,
        o.order_month,
        o.order_year,
        o.customer_id,
        o.store_id,
        o.store_channel,
        o.traffic_source,
        o.campaign_id,
        o.order_status,
        i.product_id,
        i.product_name,
        i.sku,
        i.category,
        i.subcategory,
        i.brand,
        i.quantity,
        i.unit_price_at_purchase,
        i.cost_price,
        i.line_gross_revenue,
        i.line_net_revenue,
        i.line_discount,
        i.discount_pct,
        i.unit_margin,
        i.line_margin,
        i.line_margin_pct,
        i.is_featured,
        CURRENT_TIMESTAMP()                             AS dbt_updated_at
    FROM items i
    INNER JOIN orders o ON i.order_id = o.order_id
)

SELECT * FROM joined
