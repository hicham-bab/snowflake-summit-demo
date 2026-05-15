{{
    config(materialized='ephemeral')
}}

/*
  Materialization: EPHEMERAL
  Builds monthly cohort data by joining customer acquisition dates with
  subsequent order activity. One row per customer per active month.
  Used by fct_cohort_analysis for retention curve calculations.
*/

WITH customers AS (
    SELECT
        customer_id,
        acquisition_month,
        acquisition_channel,
        customer_segment
    FROM {{ ref('atlas_platform', 'dim_customers') }}
    WHERE acquisition_date >= '2025-01-01'  -- Cohorts from 2025 forward
),

orders AS (
    SELECT
        customer_id,
        order_month,
        SUM(net_revenue)                                AS monthly_net_revenue,
        COUNT(*)                                        AS monthly_orders
    FROM {{ ref('atlas_platform', 'fct_orders') }}
    WHERE is_completed
    GROUP BY 1, 2
),

cohort_activity AS (
    SELECT
        c.customer_id,
        c.acquisition_month                             AS cohort_month,
        c.acquisition_channel,
        c.customer_segment,
        o.order_month                                   AS activity_month,
        DATEDIFF(
            'month',
            c.acquisition_month,
            o.order_month
        )                                               AS months_since_acquisition,
        o.monthly_net_revenue,
        o.monthly_orders
    FROM customers c
    LEFT JOIN orders o ON c.customer_id = o.customer_id
)

SELECT * FROM cohort_activity
