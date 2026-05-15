{{
    config(materialized='view')
}}

WITH source AS (
    SELECT * FROM {{ source('ecommerce_raw', 'raw_returns') }}
),

renamed AS (
    SELECT
        return_id,
        order_id,
        customer_id,
        store_id,
        order_date,
        return_date,
        DATEDIFF('day', order_date, return_date)        AS days_to_return,
        return_reason,
        resolution_type,
        refund_amount,
        UPPER(return_status)                            AS return_status,

        -- Is this a valid return (approved)?
        return_status = 'APPROVED'                      AS is_approved

    FROM source
)

SELECT * FROM renamed
