{{
    config(materialized='ephemeral')
}}

/*
  Materialization: EPHEMERAL
  Builds a refund view from fct_orders (which already has return fields embedded).
  Using a public platform model avoids a cross-project dep on a private staging model.
*/

SELECT
    ROW_NUMBER() OVER (ORDER BY order_id)               AS return_id,
    order_id,
    customer_id,
    store_id,
    store_channel,
    store_region,
    campaign_id,
    order_date,
    return_date,
    DATEDIFF('day', order_date, return_date)            AS days_to_return,
    return_reason,
    COALESCE(refund_amount, 0)                          AS refund_amount,
    gross_revenue                                       AS original_order_gross_revenue,
    net_revenue                                         AS original_order_net_revenue,
    ROUND(
        COALESCE(refund_amount, 0) / NULLIF(gross_revenue, 0) * 100,
        2
    )                                                   AS refund_as_pct_of_order,
    DATE_TRUNC('month', return_date)                    AS return_month,
    QUARTER(return_date)                                AS return_quarter,
    YEAR(return_date)                                   AS return_year

FROM {{ ref('atlas_platform', 'fct_orders') }}
WHERE is_returned
  AND return_date IS NOT NULL
  AND refund_amount IS NOT NULL
