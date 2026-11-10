-- Materialization set in dbt_project.yml: view on Snowflake, Lake Compute table in Lake Compute mode.
WITH source AS (
    SELECT * FROM {{ ref('lnd_raw_customers') }}
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
        CAST(DATE_TRUNC('month', acquisition_date) AS DATE)          AS acquisition_month,
        CAST(DATE_TRUNC('quarter', acquisition_date) AS DATE)        AS acquisition_quarter,
        YEAR(acquisition_date)                         AS acquisition_year,

        -- Days since acquisition (for tenure analysis)
        DATEDIFF('day', acquisition_date, CURRENT_DATE) AS days_since_acquisition,

        created_at,
        updated_at
    FROM source
)

SELECT * FROM renamed
