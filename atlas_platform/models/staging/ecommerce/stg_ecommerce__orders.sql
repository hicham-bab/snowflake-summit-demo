{{
    config(materialized='view')
}}

WITH source AS (
    SELECT * FROM {{ source('ecommerce_raw', 'raw_orders') }}
),

renamed AS (
    SELECT
        order_id,
        order_date,
        ordered_at,
        customer_id,
        store_id,
        UPPER(status)                                   AS order_status,
        COALESCE(discount_amount, 0.00)                 AS discount_amount,
        payment_method,
        campaign_id::INT                                AS campaign_id,
        traffic_source,
        item_count,

        -- Derived flags
        order_status = 'COMPLETED'                      AS is_completed,
        order_status = 'RETURNED'                       AS is_returned,
        order_status = 'CANCELLED'                      AS is_cancelled,
        discount_amount > 0                             AS has_discount,

        -- Date parts for partitioning in downstream models
        DATE_TRUNC('month', order_date)                 AS order_month,
        DATE_TRUNC('week',  order_date)                 AS order_week,
        DAYOFWEEK(order_date)                           AS order_day_of_week,
        MONTH(order_date)                               AS order_month_num,
        QUARTER(order_date)                             AS order_quarter,
        YEAR(order_date)                                AS order_year,

        _loaded_at
    FROM source
)

SELECT * FROM renamed
