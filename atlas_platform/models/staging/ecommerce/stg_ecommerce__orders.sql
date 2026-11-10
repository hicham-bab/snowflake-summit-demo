-- Materialization set in dbt_project.yml: view on Snowflake, Iceberg table in Lake Compute mode.
WITH source AS (
    SELECT * FROM {{ ref('lnd_raw_orders') }}
),

renamed AS (
    SELECT
        -- Explicit types so incremental marts do not break when seeds are reloaded
        -- or when this model runs on Lake Compute.
        CAST(order_id AS BIGINT)                        AS order_id,
        CAST(order_date AS DATE)                        AS order_date,
        CAST(ordered_at AS TIMESTAMP)                   AS ordered_at,
        CAST(customer_id AS BIGINT)                     AS customer_id,
        CAST(store_id AS BIGINT)                        AS store_id,
        UPPER(status)                                   AS order_status,
        CAST(COALESCE(discount_amount, 0) AS DECIMAL(12,2)) AS discount_amount,
        payment_method,
        CAST(campaign_id AS INT)                                AS campaign_id,
        traffic_source,
        item_count,

        -- Derived flags
        order_status = 'COMPLETED'                      AS is_completed,
        order_status = 'RETURNED'                       AS is_returned,
        order_status = 'CANCELLED'                      AS is_cancelled,
        discount_amount > 0                             AS has_discount,

        -- Date parts for partitioning in downstream models
        CAST(DATE_TRUNC('month', order_date) AS DATE)                 AS order_month,
        CAST(DATE_TRUNC('week', order_date) AS DATE)                 AS order_week,
        DAYOFWEEK(order_date)                           AS order_day_of_week,
        MONTH(order_date)                               AS order_month_num,
        QUARTER(order_date)                             AS order_quarter,
        YEAR(order_date)                                AS order_year,

        CAST(_loaded_at AS TIMESTAMP)                   AS _loaded_at
    FROM source
)

SELECT * FROM renamed
