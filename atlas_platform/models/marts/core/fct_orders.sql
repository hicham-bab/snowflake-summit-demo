{{
    config(
        materialized='table',
        schema='marts_core',
        cluster_by=['order_date', 'store_id'],
        tags=['mart', 'core', 'published'],
        access='public'
    )
}}

/*
  Materialization: TABLE.
  This model aggregates mutable line-item data, so each build replaces the
  complete relation to keep order revenue aligned with the current source
  snapshot. Clustered by order_date + store_id for efficient pruning.

  This is the central fact table for the platform — consumed by both
  atlas_marketing and atlas_finance via dbt Mesh cross-project refs.
*/

WITH orders AS (
    SELECT * FROM {{ ref('int_orders_enriched') }}
)

SELECT
    order_id,
    order_date,
    ordered_at,
    customer_id,
    store_id,
    store_name,
    store_type,
    store_channel,
    store_city,
    store_state,
    store_region,
    order_status,
    is_completed,
    is_returned,
    is_cancelled,
    payment_method,
    campaign_id,
    traffic_source,
    has_discount,
    order_level_discount,
    item_count,
    order_month,
    order_week,
    order_quarter,
    order_year,
    gross_revenue,
    net_revenue,
    total_units,
    distinct_products,
    estimated_tax,
    refund_amount,
    return_reason,
    return_date,
    has_return,

    -- Revenue net of returns
    CASE
        WHEN is_returned AND has_return
        THEN GREATEST(net_revenue - COALESCE(refund_amount, 0), 0)
        ELSE net_revenue
    END                                                 AS realized_revenue,

    _loaded_at,
    CURRENT_TIMESTAMP()                                 AS dbt_updated_at

FROM orders
