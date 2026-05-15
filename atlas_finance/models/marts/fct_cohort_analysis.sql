{{
    config(
        materialized='table',
        schema='marts_finance',
        tags=['mart', 'finance']
    )
}}

/*
  Materialization: TABLE — cohort data is fully recomputed each run.
  Cohort retention curves are used in the investor deck and quarterly reviews.
*/

WITH cohorts AS (
    SELECT * FROM {{ ref('int_customer_cohorts') }}
),

cohort_sizes AS (
    SELECT
        cohort_month,
        acquisition_channel,
        customer_segment,
        COUNT(DISTINCT customer_id)                     AS cohort_size
    FROM cohorts
    GROUP BY 1, 2, 3
),

cohort_revenue AS (
    SELECT
        cohort_month,
        activity_month,
        months_since_acquisition,
        acquisition_channel,
        customer_segment,
        COUNT(DISTINCT customer_id)                     AS active_customers,
        SUM(monthly_net_revenue)                        AS cohort_net_revenue,
        AVG(monthly_net_revenue)                        AS avg_customer_revenue
    FROM cohorts
    WHERE activity_month IS NOT NULL
    GROUP BY 1, 2, 3, 4, 5
)

SELECT
    r.cohort_month,
    r.activity_month,
    r.months_since_acquisition,
    r.acquisition_channel,
    r.customer_segment,
    s.cohort_size,
    r.active_customers,
    r.cohort_net_revenue,
    r.avg_customer_revenue,

    -- Retention rate: % of original cohort still purchasing
    ROUND(r.active_customers::FLOAT / NULLIF(s.cohort_size, 0) * 100, 2)
                                                        AS retention_rate_pct,

    -- Cumulative cohort revenue
    SUM(r.cohort_net_revenue) OVER (
        PARTITION BY r.cohort_month, r.acquisition_channel, r.customer_segment
        ORDER BY r.months_since_acquisition
    )                                                   AS cumulative_cohort_revenue,

    CURRENT_TIMESTAMP()                                 AS dbt_updated_at

FROM cohort_revenue r
JOIN cohort_sizes s
    ON  r.cohort_month         = s.cohort_month
    AND r.acquisition_channel  = s.acquisition_channel
    AND r.customer_segment     = s.customer_segment
