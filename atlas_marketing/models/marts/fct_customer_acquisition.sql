{{
    config(
        materialized='table',
        schema='marts_marketing',
        tags=['mart', 'marketing']
    )
}}

/*
  BUG #1 (for dbt Copilot demo): This model references stg_marketing__leads,
  which does not exist. dbt compilation will fail with a "node not found" error.
  Copilot will diagnose the broken ref and suggest either:
    a) Creating the missing stg_marketing__leads model, or
    b) Removing the join if leads data is not yet available.

  The fix is to remove the leads CTE and join — the model works fine without it.
*/

WITH customers AS (
    SELECT
        customer_id,
        full_name,
        acquisition_channel,
        acquisition_date,
        acquisition_month,
        acquisition_quarter,
        acquisition_year,
        customer_segment,
        customer_value_tier,
        lifetime_net_revenue,
        total_orders,
        first_order_date,
        avg_order_value
    FROM {{ ref('atlas_platform', 'dim_customers') }}
),

campaigns AS (
    SELECT
        campaign_id,
        campaign_name,
        channel,
        budget_usd,
        start_date,
        campaign_start_month
    FROM {{ ref('stg_marketing__campaigns') }}
),

acquisition_summary AS (
    SELECT
        c.acquisition_channel,
        c.acquisition_month,
        c.acquisition_quarter,
        c.acquisition_year,
        COUNT(DISTINCT c.customer_id)                   AS new_customers,
        SUM(c.lifetime_net_revenue)                     AS cohort_ltv,
        AVG(c.lifetime_net_revenue)                     AS avg_cohort_ltv,
        AVG(c.total_orders)                             AS avg_orders_per_customer,
        SUM(CASE WHEN c.customer_value_tier = 'high_value' THEN 1 ELSE 0 END)
                                                        AS high_value_customers
    FROM customers c
    GROUP BY 1, 2, 3, 4
)

SELECT a.*
FROM acquisition_summary a
