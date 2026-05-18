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
    DROP TABLE IF EXISTS ATLAS_PLATFORM.PUBLIC.STORE_KPI_DAILY;

    -- orders
    CREATE TABLE ATLAS_PLATFORM.PUBLIC.T1 AS
    SELECT
        o.store_id,
        o.order_date,
        o.order_id,
        o.order_status,
        o.gross_revenue,
        o.net_revenue,
        o.refund_amount,
        o.is_returned,
        o.customer_id
    FROM ATLAS_PLATFORM.RAW.RAW_ORDERS o
    WHERE o.order_date >= :d1 AND o.order_date <= :d2;

    -- items
    -- NOTE: had to add this join in nov because someone asked about categories
    -- not sure if its still needed
    CREATE TABLE ATLAS_PLATFORM.PUBLIC.T2 AS
    SELECT
        i.order_id,
        i.category,
        i.quantity,
        SUM(i.quantity * i.unit_price) AS item_rev
    FROM ATLAS_PLATFORM.RAW.RAW_ORDER_ITEMS i
    WHERE EXISTS (SELECT 1 FROM ATLAS_PLATFORM.PUBLIC.T1 t WHERE t.order_id = i.order_id)
    GROUP BY 1, 2, 3;

    -- top category per order (approx)
    CREATE TABLE ATLAS_PLATFORM.PUBLIC.T3 AS
    SELECT order_id, category
    FROM (
        SELECT order_id, category, item_rev,
               ROW_NUMBER() OVER (PARTITION BY order_id ORDER BY item_rev DESC) rn
        FROM ATLAS_PLATFORM.PUBLIC.T2
    ) WHERE rn = 1;

    -- final
    CREATE TABLE ATLAS_PLATFORM.PUBLIC.STORE_KPI_DAILY AS
    SELECT
        s.store_id,
        s.store_name,
        s.channel,
        s.region,
        t1.order_date,
        COUNT(t1.order_id)                                              tot_orders,
        COUNT(CASE WHEN t1.order_status = 'COMPLETED' THEN 1 END)      comp_orders,
        COUNT(CASE WHEN t1.order_status = 'RETURNED'  THEN 1 END)      ret_orders,
        -- BUG: divides by tot_orders not comp_orders, inflates return rate
        -- when there are cancelled orders in the mix
        ROUND(COUNT(CASE WHEN t1.order_status = 'RETURNED' THEN 1 END)
            / NULLIF(COUNT(t1.order_id), 0) * 100, 2)                  ret_rate_pct,
        SUM(CASE WHEN t1.order_status = 'COMPLETED'
                 THEN t1.gross_revenue ELSE 0 END)                      gross_rev,
        SUM(CASE WHEN t1.order_status = 'COMPLETED'
                 THEN t1.net_revenue ELSE 0 END)                        net_rev,
        -- BUG: refunds summed regardless of status — includes non-returned orders
        SUM(COALESCE(t1.refund_amount, 0))                              refunds,
        -- should be net_rev - refunds but copy-paste left gross_rev here
        SUM(CASE WHEN t1.order_status = 'COMPLETED'
                 THEN t1.gross_revenue ELSE 0 END)
            - SUM(COALESCE(t1.refund_amount, 0))                        realized_rev,
        AVG(CASE WHEN t1.order_status = 'COMPLETED'
                 THEN t1.gross_revenue END)                             aov,
        COUNT(DISTINCT t1.customer_id)                                  uniq_custs,
        -- hardcoded: performance tier based on daily net rev
        -- thresholds picked by jake eyeballing last years data, never revisited
        CASE
            WHEN SUM(CASE WHEN t1.order_status = 'COMPLETED'
                     THEN t1.net_revenue ELSE 0 END) >= 15000 THEN 'A'
            WHEN SUM(CASE WHEN t1.order_status = 'COMPLETED'
                     THEN t1.net_revenue ELSE 0 END) >= 7000  THEN 'B'
            WHEN SUM(CASE WHEN t1.order_status = 'COMPLETED'
                     THEN t1.net_revenue ELSE 0 END) >= 2000  THEN 'C'
            ELSE 'D'
        END                                                             perf_tier,
        t3.category                                                     top_cat,
        CURRENT_TIMESTAMP()                                             ts
    FROM ATLAS_PLATFORM.SEEDS.CATALOG_STORES s
    LEFT JOIN ATLAS_PLATFORM.PUBLIC.T1 t1 ON s.store_id = t1.store_id
    LEFT JOIN ATLAS_PLATFORM.PUBLIC.T3 t3 ON t1.order_id = t3.order_id
    GROUP BY 1,2,3,4,5,25,26;

    n := SQLROWCOUNT;

    -- TODO: add row count check someday

    RETURN 'done ' || n;
END;
$$;


-- run it:
-- CALL ATLAS_PLATFORM.PUBLIC.SP_STORE_KPI_DAILY();
-- SELECT * FROM ATLAS_PLATFORM.PUBLIC.STORE_KPI_DAILY ORDER BY order_date DESC;
