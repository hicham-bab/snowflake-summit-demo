-- Materialization set in dbt_project.yml: view on Snowflake, Iceberg table in Lake Compute mode.
WITH source AS (
    SELECT * FROM {{ ref('lnd_raw_returns') }}
),

renamed AS (
    SELECT
        return_id,
        CAST(order_id AS BIGINT)                        AS order_id,
        CAST(customer_id AS BIGINT)                     AS customer_id,
        CAST(store_id AS BIGINT)                        AS store_id,
        order_date,
        return_date,
        DATEDIFF('day', order_date, return_date)        AS days_to_return,
        return_reason,
        resolution_type,
        CAST(refund_amount AS DECIMAL(12,2))            AS refund_amount,
        UPPER(return_status)                            AS return_status,

        -- Is this a valid return (approved)?
        return_status = 'APPROVED'                      AS is_approved

    FROM source
)

SELECT * FROM renamed
