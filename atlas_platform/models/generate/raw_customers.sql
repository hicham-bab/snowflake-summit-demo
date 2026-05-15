{{
    config(
        materialized='table',
        schema='raw',
        tags=['generate', 'raw_data']
    )
}}

/*
  Generates 12,000 synthetic customers with realistic US demographics.
  Acquisition dates span from 2022 (long-term loyalists) through June 2026.
  Run once to seed the raw layer before building staging/mart models.
*/

WITH customer_gen AS (
    SELECT
        seq4() + 1 AS customer_id,
        CASE (seq4() % 20)
            WHEN 0  THEN 'Emma'   WHEN 1  THEN 'Liam'   WHEN 2  THEN 'Olivia'
            WHEN 3  THEN 'Noah'   WHEN 4  THEN 'Ava'    WHEN 5  THEN 'William'
            WHEN 6  THEN 'Sophia' WHEN 7  THEN 'James'  WHEN 8  THEN 'Isabella'
            WHEN 9  THEN 'Oliver' WHEN 10 THEN 'Mia'    WHEN 11 THEN 'Benjamin'
            WHEN 12 THEN 'Charlotte' WHEN 13 THEN 'Elijah' WHEN 14 THEN 'Amelia'
            WHEN 15 THEN 'Lucas'  WHEN 16 THEN 'Harper' WHEN 17 THEN 'Mason'
            WHEN 18 THEN 'Evelyn' WHEN 19 THEN 'Logan'
        END AS first_name,
        CASE (seq4() % 25)
            WHEN 0  THEN 'Smith'    WHEN 1  THEN 'Johnson' WHEN 2  THEN 'Williams'
            WHEN 3  THEN 'Brown'    WHEN 4  THEN 'Jones'   WHEN 5  THEN 'Garcia'
            WHEN 6  THEN 'Miller'   WHEN 7  THEN 'Davis'   WHEN 8  THEN 'Rodriguez'
            WHEN 9  THEN 'Martinez' WHEN 10 THEN 'Hernandez' WHEN 11 THEN 'Lopez'
            WHEN 12 THEN 'Gonzalez' WHEN 13 THEN 'Wilson'  WHEN 14 THEN 'Anderson'
            WHEN 15 THEN 'Thomas'   WHEN 16 THEN 'Taylor'  WHEN 17 THEN 'Moore'
            WHEN 18 THEN 'Jackson'  WHEN 19 THEN 'Martin'  WHEN 20 THEN 'Lee'
            WHEN 21 THEN 'Perez'    WHEN 22 THEN 'Thompson' WHEN 23 THEN 'White'
            WHEN 24 THEN 'Harris'
        END AS last_name,
        CASE (seq4() % 6)
            WHEN 0 THEN 'gmail.com'    WHEN 1 THEN 'yahoo.com'
            WHEN 2 THEN 'outlook.com'  WHEN 3 THEN 'icloud.com'
            WHEN 4 THEN 'hotmail.com'  WHEN 5 THEN 'proton.me'
        END AS email_domain,
        CASE (seq4() % 6)
            WHEN 0 THEN 'New York'      WHEN 1 THEN 'Los Angeles'
            WHEN 2 THEN 'Chicago'       WHEN 3 THEN 'Houston'
            WHEN 4 THEN 'Phoenix'       WHEN 5 THEN 'Philadelphia'
        END AS city,
        CASE (seq4() % 6)
            WHEN 0 THEN 'NY' WHEN 1 THEN 'CA' WHEN 2 THEN 'IL'
            WHEN 3 THEN 'TX' WHEN 4 THEN 'AZ' WHEN 5 THEN 'PA'
        END AS state,
        CASE
            WHEN UNIFORM(1, 100, RANDOM()) <= 5  THEN 'VIP'
            WHEN UNIFORM(1, 100, RANDOM()) <= 25 THEN 'Premium'
            WHEN UNIFORM(1, 100, RANDOM()) <= 60 THEN 'Regular'
            ELSE 'Budget'
        END AS customer_segment,
        CASE (seq4() % 4)
            WHEN 0 THEN 'paid_search'
            WHEN 1 THEN 'paid_social'
            WHEN 2 THEN 'organic'
            WHEN 3 THEN 'referral'
        END AS acquisition_channel,
        DATEADD('day', -(UNIFORM(1, 1460, RANDOM())), CURRENT_DATE()) AS acquisition_date,
        UNIFORM(18, 65, RANDOM()) AS age,
        CASE WHEN UNIFORM(1, 2, RANDOM()) = 1 THEN 'M' ELSE 'F' END AS gender,
        TRUE AS is_email_subscribed,
        CASE WHEN UNIFORM(1, 100, RANDOM()) <= 35 THEN TRUE ELSE FALSE END AS is_sms_subscribed,
        CURRENT_TIMESTAMP() AS created_at,
        CURRENT_TIMESTAMP() AS updated_at
    FROM TABLE(GENERATOR(ROWCOUNT => 12000))
)

SELECT
    customer_id,
    first_name,
    last_name,
    LOWER(first_name) || '.' || LOWER(last_name) || CAST(customer_id AS VARCHAR) || '@' || email_domain AS email,
    city,
    state,
    customer_segment,
    acquisition_channel,
    acquisition_date,
    age,
    gender,
    is_email_subscribed,
    is_sms_subscribed,
    created_at,
    updated_at
FROM customer_gen
