-- sp_store_kpi_daily.sql
-- do not edit without asking jake first
-- last updated sometime in Q3

CREATE OR REPLACE PROCEDURE ATLAS_PLATFORM.PUBLIC.SP_STORE_KPI_DAILY()
RETURNS VARCHAR
LANGUAGE SQL
AS
$$
DECLARE
    d1 DATE;
    d2 DATE;
    n  INT;
    x  FLOAT;
BEGIN

    d1 := '2025-06-01';
    d2 := CURRENT_DATE();

    -- clean up
    DROP TABLE IF EXISTS ATLAS_PLATFORM.PUBLIC.T1;
    DROP TABLE IF EXISTS ATLAS_PLATFORM.PUBLIC.T2;
    DROP TABLE IF EXISTS ATLAS_PLATFORM.PUBLIC.T3;
    DROP TABLE IF EXISTS ATLAS_PLATFORM.PUBLIC.T4;
    DROP TABLE IF EXISTS ATLAS_PLATFORM.PUBLIC.T5;
    DROP TABLE IF EXISTS ATLAS_PLATFORM.PUBLIC.STORE_KPI_DAILY;

    -- orders (raw table uses 'status' not 'order_status')
    CREATE TABLE ATLAS_PLATFORM.PUBLIC.T1 AS
    SELECT
        o.store_id,
        o.order_date,
        o.order_id,
        UPPER(o.status)     AS order_status,
        o.customer_id
    FROM ATLAS_PLATFORM.RAW.RAW_ORDERS o
    WHERE o.order_date >= :d1 AND o.order_date <= :d2;

    -- revenue from items (raw_orders has no revenue columns)
    CREATE TABLE ATLAS_PLATFORM.PUBLIC.T2 AS
    SELECT
        i.order_id,
        i.category,
        SUM(i.line_gross_revenue)   AS gross_rev,
        SUM(i.line_net_revenue)     AS net_rev
    FROM ATLAS_PLATFORM.RAW.RAW_ORDER_ITEMS i
    WHERE EXISTS (SELECT 1 FROM ATLAS_PLATFORM.PUBLIC.T1 t WHERE t.order_id = i.order_id)
    GROUP BY 1, 2;

    -- revenue per order (all categories combined)
    CREATE TABLE ATLAS_PLATFORM.PUBLIC.T3 AS
    SELECT order_id,
           SUM(gross_rev)   AS gross_rev,
           SUM(net_rev)     AS net_rev
    FROM ATLAS_PLATFORM.PUBLIC.T2
    GROUP BY 1;

    -- top category per order (approx — not per store-day, just per order)
    -- NOTE: had to add this in nov because someone asked about categories
    -- not sure if its still needed
    CREATE TABLE ATLAS_PLATFORM.PUBLIC.T4 AS
    SELECT order_id, category
    FROM (
        SELECT order_id, category, gross_rev,
               ROW_NUMBER() OVER (PARTITION BY order_id ORDER BY gross_rev DESC) rn
        FROM ATLAS_PLATFORM.PUBLIC.T2
    ) WHERE rn = 1;

    -- refunds (from raw_returns, not embedded in raw_orders)
    CREATE TABLE ATLAS_PLATFORM.PUBLIC.T5 AS
    SELECT r.order_id, r.refund_amount
    FROM ATLAS_PLATFORM.RAW.RAW_RETURNS r
    WHERE EXISTS (SELECT 1 FROM ATLAS_PLATFORM.PUBLIC.T1 t WHERE t.order_id = r.order_id);

    -- final
    CREATE TABLE ATLAS_PLATFORM.PUBLIC.STORE_KPI_DAILY AS
    SELECT
        s.store_id,
        s.store_name,
        s.channel,
        s.region,
        t1.order_date,
        COUNT(t1.order_id)                                                              tot_orders,
        COUNT(CASE WHEN t1.order_status = 'COMPLETED' THEN 1 END)                      comp_orders,
        COUNT(CASE WHEN t1.order_status = 'RETURNED'  THEN 1 END)                      ret_orders,
        -- BUG: divides by tot_orders not comp_orders, inflates return rate
        -- when there are cancelled orders in the mix
        ROUND(COUNT(CASE WHEN t1.order_status = 'RETURNED' THEN 1 END)
            / NULLIF(COUNT(t1.order_id), 0) * 100, 2)                                  ret_rate_pct,
        SUM(CASE WHEN t1.order_status = 'COMPLETED'
                 THEN COALESCE(t3.gross_rev, 0) ELSE 0 END)                            gross_rev,
        SUM(CASE WHEN t1.order_status = 'COMPLETED'
                 THEN COALESCE(t3.net_rev, 0) ELSE 0 END)                              net_rev,
        -- BUG: refunds summed regardless of order status — includes non-returned orders
        SUM(COALESCE(t5.refund_amount, 0))                                              refunds,
        -- BUG: copy-paste left gross_rev here instead of net_rev
        SUM(CASE WHEN t1.order_status = 'COMPLETED'
                 THEN COALESCE(t3.gross_rev, 0) ELSE 0 END)
            - SUM(COALESCE(t5.refund_amount, 0))                                        realized_rev,
        AVG(CASE WHEN t1.order_status = 'COMPLETED'
                 THEN t3.gross_rev END)                                                 aov,
        COUNT(DISTINCT t1.customer_id)                                                  uniq_custs,
        -- hardcoded: performance tier based on daily net rev
        -- thresholds picked by jake eyeballing last years data, never revisited
        CASE
            WHEN SUM(CASE WHEN t1.order_status = 'COMPLETED'
                     THEN COALESCE(t3.net_rev, 0) ELSE 0 END) >= 15000 THEN 'A'
            WHEN SUM(CASE WHEN t1.order_status = 'COMPLETED'
                     THEN COALESCE(t3.net_rev, 0) ELSE 0 END) >= 7000  THEN 'B'
            WHEN SUM(CASE WHEN t1.order_status = 'COMPLETED'
                     THEN COALESCE(t3.net_rev, 0) ELSE 0 END) >= 2000  THEN 'C'
            ELSE 'D'
        END                                                                             perf_tier,
        t4.category                                                                     top_cat,
        CURRENT_TIMESTAMP()                                                             ts
    FROM ATLAS_PLATFORM.SEEDS.CATALOG_STORES s
    LEFT JOIN ATLAS_PLATFORM.PUBLIC.T1 t1 ON s.store_id  = t1.store_id
    LEFT JOIN ATLAS_PLATFORM.PUBLIC.T3 t3 ON t1.order_id = t3.order_id
    LEFT JOIN ATLAS_PLATFORM.PUBLIC.T4 t4 ON t1.order_id = t4.order_id
    LEFT JOIN ATLAS_PLATFORM.PUBLIC.T5 t5 ON t1.order_id = t5.order_id
    GROUP BY 1, 2, 3, 4, 5, t4.category;

    n := SQLROWCOUNT;

    -- TODO: add row count check someday

    RETURN 'done ' || n;
END;
$$;


-- run it:
-- CALL ATLAS_PLATFORM.PUBLIC.SP_STORE_KPI_DAILY();
-- SELECT * FROM ATLAS_PLATFORM.PUBLIC.STORE_KPI_DAILY ORDER BY order_date DESC;
