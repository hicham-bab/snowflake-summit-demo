{{
    config(
        materialized='table',
        schema='raw',
        tags=['generate', 'raw_data']
    )
}}

/*
  Generates return records for orders with status = 'returned'.
  Return window: typically 3–21 days after order date.
  Reason codes reflect realistic return patterns.
*/

SELECT
    ROW_NUMBER() OVER (ORDER BY o.order_id)     AS return_id,
    o.order_id,
    o.customer_id,
    o.store_id,
    o.order_date,
    DATEADD('day', UNIFORM(3, 21, RANDOM()), o.order_date) AS return_date,

    CASE (MOD(o.order_id, 7))
        WHEN 0 THEN 'defective_item'
        WHEN 1 THEN 'wrong_size'
        WHEN 2 THEN 'not_as_described'
        WHEN 3 THEN 'changed_mind'
        WHEN 4 THEN 'arrived_late'
        WHEN 5 THEN 'duplicate_order'
        WHEN 6 THEN 'damaged_in_shipping'
    END AS return_reason,

    CASE (MOD(o.order_id, 3))
        WHEN 0 THEN 'refund_to_original'
        WHEN 1 THEN 'store_credit'
        WHEN 2 THEN 'exchange'
    END AS resolution_type,

    ROUND(UNIFORM(15.0, 250.0, RANDOM()), 2) AS refund_amount,

    CASE WHEN UNIFORM(1, 100, RANDOM()) <= 85 THEN 'approved' ELSE 'denied' END AS return_status,

    CURRENT_TIMESTAMP() AS _loaded_at

FROM {{ ref('raw_orders') }} o
WHERE o.status = 'returned'
