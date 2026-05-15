{{
    config(
        materialized='incremental',
        schema='marts_core',
        unique_key='order_id',
        incremental_strategy='merge',
        cluster_by=['order_date', 'store_id'],
        tags=['mart', 'core', 'published'],
        access='public',
        on_schema_change='fail'
    )
}}

/*
  Materialization: INCREMENTAL (merge strategy).
  Processes only new or updated orders since the last run.
  cluster_by ['order_date', 'store_id'] enables efficient pruning on Snowflake.

  This is the central fact table for the platform — consumed by both
  atlas_marketing and atlas_finance via dbt Mesh cross-project refs.
*/

{% if is_incremental() %}
-- Compute cutoff in a standalone CTE to avoid correlated aggregate error
-- when int_orders_enriched is inlined as an ephemeral CTE by Snowflake.
WITH incremental_cutoff AS (
    SELECT DATEADD('day', -3, MAX(_loaded_at)) AS cutoff
    FROM {{ this }}
),

orders AS (
    SELECT o.*
    FROM {{ ref('int_orders_enriched') }} o
    CROSS JOIN incremental_cutoff ic
    WHERE o._loaded_at >= ic.cutoff
)

{% else %}

WITH orders AS (
    SELECT * FROM {{ ref('int_orders_enriched') }}
)

{% endif %}

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
