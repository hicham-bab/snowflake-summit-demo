{% snapshot scd_customers %}

{{
    config(
        target_schema='snapshots',
        strategy='check',
        unique_key='customer_id',
        check_cols=[
            'customer_segment',
            'customer_lifecycle_stage',
            'customer_value_tier',
            'lifetime_net_revenue',
            'total_orders',
            'last_order_date',
            'is_email_subscribed',
            'is_sms_subscribed'
        ],
        invalidate_hard_deletes=True,
        tags=['snapshot', 'scd', 'core']
    )
}}

/*
  Materialization: SNAPSHOT (SCD Type 2).
  Captures historical changes to customer segment, lifecycle stage, and value tier.
  Each change creates a new record with dbt_valid_from / dbt_valid_to timestamps.

  Demo talking point: "This lets us answer 'what was this customer's segment
  during BFCM 2025?' — time-travel on customer data without complex SCD logic."

  Run manually: dbt snapshot --select scd_customers
*/

SELECT
    customer_id,
    full_name,
    email,
    customer_segment,
    customer_lifecycle_stage,
    customer_value_tier,
    acquisition_channel,
    acquisition_date,
    total_orders,
    lifetime_net_revenue,
    avg_order_value,
    last_order_date,
    is_email_subscribed,
    is_sms_subscribed,
    CURRENT_TIMESTAMP() AS updated_at

FROM {{ ref('dim_customers') }}

{% endsnapshot %}
