{{
    config(materialized='ephemeral')
}}

/*
  Materialization: EPHEMERAL — inlined as a CTE into downstream models.
  This keeps intermediate business logic encapsulated without creating
  a physical table. Use `dbt compile` to see the inlined SQL in fct_orders.
*/

WITH orders AS (
    SELECT * FROM {{ ref('stg_ecommerce__orders') }}
),

order_items_agg AS (
    SELECT
        order_id,
        SUM(line_gross_revenue)             AS gross_revenue,
        SUM(line_net_revenue)               AS net_revenue,
        SUM(line_discount)                  AS total_item_discount,
        SUM(quantity)                       AS total_units,
        COUNT(DISTINCT product_id)          AS distinct_products
    FROM {{ ref('stg_ecommerce__order_items') }}
    GROUP BY 1
),

returns AS (
    SELECT
        order_id,
        refund_amount,
        return_reason,
        return_date
    FROM {{ ref('stg_ecommerce__returns') }}
    WHERE is_approved
),

stores AS (
    SELECT store_id, store_name, store_type, channel, city, state, region
    FROM {{ ref('catalog_stores') }}
),

enriched AS (
    SELECT
        o.order_id,
        o.order_date,
        o.ordered_at,
        o.customer_id,
        o.store_id,
        s.store_name,
        s.store_type,
        s.channel                                       AS store_channel,
        s.city                                          AS store_city,
        s.state                                         AS store_state,
        s.region                                        AS store_region,
        o.order_status,
        o.is_completed,
        o.is_returned,
        o.is_cancelled,
        o.payment_method,
        o.campaign_id,
        o.traffic_source,
        o.has_discount,
        o.discount_amount                               AS order_level_discount,
        o.item_count,
        o.order_month,
        o.order_week,
        o.order_quarter,
        o.order_year,

        -- Revenue from line items
        COALESCE(oi.gross_revenue, 0)                   AS gross_revenue,
        COALESCE(oi.net_revenue, 0)                     AS net_revenue,
        COALESCE(oi.total_units, 0)                     AS total_units,
        COALESCE(oi.distinct_products, 0)               AS distinct_products,

        -- Tax estimate (8.5% of net revenue for completed orders)
        CASE
            WHEN o.is_completed
            THEN ROUND(COALESCE(oi.net_revenue, 0) * 0.085, 2)
            ELSE 0
        END                                             AS estimated_tax,

        -- Return info
        r.refund_amount,
        r.return_reason,
        r.return_date,
        r.refund_amount IS NOT NULL                     AS has_return

    FROM orders o
    LEFT JOIN order_items_agg oi ON o.order_id = oi.order_id
    LEFT JOIN stores s           ON o.store_id = s.store_id
    LEFT JOIN returns r          ON o.order_id = r.order_id
)

SELECT * FROM enriched
