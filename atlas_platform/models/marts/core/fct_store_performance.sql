{{
    config(
        materialized='incremental',
        schema='marts_core',
        unique_key=['store_id', 'order_date'],
        incremental_strategy='merge',
        incremental_predicates=[
            "DBT_INTERNAL_DEST.order_date >= DATEADD('day', -7, CURRENT_DATE())"
        ],
        cluster_by=['order_date', 'store_id'],
        tags=['mart', 'core', 'published'],
        access='public',
        on_schema_change='append_new_columns'
    )
}}

/*
  Materialization: INCREMENTAL (merge strategy).
  Store-day performance fact — one row per active store per reporting date.
  Rebuilds the recent reporting window on incremental runs to handle late
  order updates and returns while preserving an efficient Snowflake merge.
*/

{% set target_columns = adapter.get_columns_in_relation(this) if is_incremental() else [] %}
{% set target_column_names = target_columns | map(attribute='name') | map('lower') | list %}

WITH dates AS (
    SELECT
        date_day AS order_date
    FROM {{ ref('dim_dates') }}
    WHERE date_day BETWEEN '{{ var("start_date") }}'::DATE AND '{{ var("end_date") }}'::DATE

    {% if is_incremental() and 'order_date' in target_column_names %}
        AND date_day >= (
            SELECT DATEADD('day', -3, MAX(order_date))
            FROM {{ this }}
        )
    {% endif %}
),

stores AS (
    SELECT
        store_id,
        store_name,
        channel,
        region,
        is_active
    FROM {{ ref('dim_stores') }}
    WHERE is_active
),

store_dates AS (
    SELECT
        stores.store_id,
        stores.store_name,
        stores.channel,
        stores.region,
        dates.order_date
    FROM stores
    CROSS JOIN dates
),

orders AS (
    SELECT
        order_id,
        order_date,
        store_id,
        customer_id,
        is_completed,
        is_returned,
        gross_revenue,
        net_revenue,
        realized_revenue,
        refund_amount
    FROM {{ ref('fct_orders') }}
    WHERE order_date IN (SELECT order_date FROM dates)
),

order_metrics AS (
    SELECT
        store_id,
        order_date,
        COUNT(*)                                            AS total_orders,
        COUNT_IF(is_completed)                              AS completed_orders,
        COUNT_IF(is_returned)                               AS returned_orders,
        COUNT(DISTINCT customer_id)                         AS unique_customers,
        COALESCE(SUM(IFF(is_completed, gross_revenue, 0)), 0) AS gross_revenue,
        COALESCE(SUM(IFF(is_completed, net_revenue, 0)), 0)  AS net_revenue,
        COALESCE(SUM(realized_revenue), 0)                  AS realized_revenue,
        COALESCE(SUM(refund_amount), 0)                     AS refund_amount
    FROM orders
    GROUP BY 1, 2
),

category_metrics AS (
    SELECT
        store_id,
        order_date,
        category,
        SUM(line_gross_revenue)                             AS category_gross_revenue,
        ROW_NUMBER() OVER (
            PARTITION BY store_id, order_date
            ORDER BY SUM(line_gross_revenue) DESC, category
        )                                                   AS category_rank
    FROM {{ ref('fct_order_items') }}
    WHERE order_date IN (SELECT order_date FROM dates)
        AND order_status = 'COMPLETED'
    GROUP BY 1, 2, 3
),

top_categories AS (
    SELECT
        store_id,
        order_date,
        category                                            AS top_category
    FROM category_metrics
    WHERE category_rank = 1
),

final AS (
    SELECT
        store_dates.store_id,
        store_dates.order_date,
        store_dates.store_name,
        store_dates.channel,
        store_dates.region,
        COALESCE(order_metrics.total_orders, 0)             AS total_orders,
        COALESCE(order_metrics.completed_orders, 0)         AS completed_orders,
        COALESCE(order_metrics.returned_orders, 0)          AS returned_orders,
        COALESCE(order_metrics.unique_customers, 0)         AS unique_customers,
        COALESCE(order_metrics.gross_revenue, 0)            AS gross_revenue,
        COALESCE(order_metrics.net_revenue, 0)              AS net_revenue,
        COALESCE(order_metrics.realized_revenue, 0)         AS realized_revenue,
        COALESCE(order_metrics.refund_amount, 0)            AS refund_amount,
        top_categories.top_category,
        CASE
            WHEN COALESCE(order_metrics.completed_orders, 0) = 0 THEN 0
            ELSE order_metrics.gross_revenue / order_metrics.completed_orders
        END                                                 AS average_order_value,
        CASE
            WHEN COALESCE(order_metrics.total_orders, 0) = 0 THEN 0
            ELSE (order_metrics.returned_orders / order_metrics.total_orders) * 100
        END                                                 AS return_rate_pct,
        CASE
            WHEN COALESCE(order_metrics.net_revenue, 0) >= 10000 THEN 'A'
            WHEN COALESCE(order_metrics.net_revenue, 0) >= 5000 THEN 'B'
            WHEN COALESCE(order_metrics.net_revenue, 0) >= 1000 THEN 'C'
            ELSE 'D'
        END                                                 AS performance_tier,
        CURRENT_TIMESTAMP()                                 AS dbt_updated_at
    FROM store_dates
    LEFT JOIN order_metrics
        ON store_dates.store_id = order_metrics.store_id
        AND store_dates.order_date = order_metrics.order_date
    LEFT JOIN top_categories
        ON store_dates.store_id = top_categories.store_id
        AND store_dates.order_date = top_categories.order_date
)

SELECT * FROM final
