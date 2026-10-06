/*
  Protects executive revenue reporting by requiring staging, order-grain,
  and line-item-grain net revenue to agree for every order.
  This test returns only mismatched orders; zero rows means it passes.
*/

WITH staging_by_order AS (
    SELECT
        order_id,
        SUM(line_net_revenue) AS staging_net_revenue
    FROM {{ ref('stg_ecommerce__order_items') }}
    GROUP BY 1
),

order_fact AS (
    SELECT
        order_id,
        net_revenue AS order_net_revenue
    FROM {{ ref('fct_orders') }}
),

item_fact_by_order AS (
    SELECT
        order_id,
        SUM(line_net_revenue) AS item_net_revenue
    FROM {{ ref('fct_order_items') }}
    GROUP BY 1
),

reconciled AS (
    SELECT
        COALESCE(s.order_id, o.order_id, i.order_id) AS order_id,
        s.staging_net_revenue,
        o.order_net_revenue,
        i.item_net_revenue
    FROM staging_by_order s
    FULL OUTER JOIN order_fact o USING (order_id)
    FULL OUTER JOIN item_fact_by_order i
        ON COALESCE(s.order_id, o.order_id) = i.order_id
)

SELECT *
FROM reconciled
WHERE order_net_revenue IS NULL
   OR (staging_net_revenue IS NULL AND COALESCE(order_net_revenue, 0) <> 0)
   OR (item_net_revenue IS NULL AND staging_net_revenue IS NOT NULL)
   OR ABS(COALESCE(staging_net_revenue, 0) - COALESCE(order_net_revenue, 0)) > 0.01
   OR ABS(COALESCE(staging_net_revenue, 0) - COALESCE(item_net_revenue, 0)) > 0.01
