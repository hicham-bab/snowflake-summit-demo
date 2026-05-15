{{
    config(materialized='view')
}}

WITH source AS (
    SELECT * FROM {{ source('ecommerce_raw', 'raw_customers') }}
),

renamed AS (
    SELECT
        customer_id,
        first_name,
        last_name,
        first_name || ' ' || last_name                 AS full_name,
        LOWER(email)                                    AS email,
        city,
        state,
        customer_segment,
        acquisition_channel,
        acquisition_date,
        age,
        CASE gender
            WHEN 'M' THEN 'Male'
            WHEN 'F' THEN 'Female'
            ELSE 'Unknown'
        END                                             AS gender,
        is_email_subscribed,
        is_sms_subscribed,

        -- Derived cohort
        DATE_TRUNC('month', acquisition_date)          AS acquisition_month,
        DATE_TRUNC('quarter', acquisition_date)        AS acquisition_quarter,
        YEAR(acquisition_date)                         AS acquisition_year,

        -- Days since acquisition (for tenure analysis)
        DATEDIFF('day', acquisition_date, CURRENT_DATE()) AS days_since_acquisition,

        created_at,
        updated_at
    FROM source
)

SELECT * FROM renamed
