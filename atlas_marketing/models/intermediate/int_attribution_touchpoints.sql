{{
    config(materialized='ephemeral')
}}

/*
  Materialization: EPHEMERAL
  Builds attribution touchpoints from the event stream. Assigns credit
  to the last non-direct touch before each completed order (Last Touch Attribution).
  Ephemeral because this CTE is only used by fct_channel_attribution.
*/

WITH events AS (
    SELECT
        customer_id,
        event_date,
        session_id,
        traffic_source,
        event_type,
        product_id,
        device_type
    FROM {{ source('marketing_raw', 'raw_events') }}
    WHERE event_type IN ('purchase_completed', 'checkout_started', 'add_to_cart', 'product_view')
),

orders AS (
    SELECT
        order_id,
        order_date,
        customer_id,
        gross_revenue,
        net_revenue,
        realized_revenue,
        traffic_source  AS order_traffic_source,
        campaign_id
    FROM {{ ref('atlas_platform', 'fct_orders') }}
    WHERE is_completed
),

-- Last non-direct touch before order (within 30-day attribution window)
pre_order_events AS (
    SELECT
        o.order_id,
        o.order_date,
        o.customer_id,
        o.gross_revenue,
        o.net_revenue,
        o.realized_revenue,
        o.order_traffic_source,
        e.session_id,
        e.traffic_source                                AS touchpoint_source,
        e.event_date                                    AS touchpoint_date,
        e.device_type,
        ROW_NUMBER() OVER (
            PARTITION BY o.order_id
            ORDER BY e.event_date DESC, e.session_id DESC
        )                                               AS touchpoint_recency_rank
    FROM orders o
    JOIN events e
        ON  e.customer_id = o.customer_id
        AND e.event_date BETWEEN DATEADD('day', -30, o.order_date) AND o.order_date
        AND e.traffic_source != 'direct'  -- exclude direct from last-touch
),

last_touch AS (
    SELECT * FROM pre_order_events
    WHERE touchpoint_recency_rank = 1
)

SELECT
    order_id,
    order_date,
    customer_id,
    gross_revenue,
    net_revenue,
    realized_revenue,
    order_traffic_source,
    COALESCE(touchpoint_source, order_traffic_source) AS attributed_channel,
    touchpoint_date,
    device_type

FROM last_touch
