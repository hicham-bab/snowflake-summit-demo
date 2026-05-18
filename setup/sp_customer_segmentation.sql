-- =============================================================================
-- Stored Procedure: SP_BUILD_CUSTOMER_SEGMENTS
-- Purpose:         Calculates customer lifetime metrics, assigns value tiers
--                  (VIP / Premium / Regular / Budget) and lifecycle stages
--                  (active / at_risk / churned / never_purchased).
--                  Truncates and fully reloads DIM_CUSTOMERS on every run.
-- Schedule:        Nightly at 02:00 UTC via Snowflake Task
-- Owner:           data-team@atlas.com
-- Last modified:   2025-10-22
-- WARNING:         Hardcoded to ATLAS_PLATFORM database.
--                  All thresholds below are hard-coded — any business rule
--                  change requires editing this procedure directly.
-- =============================================================================

CREATE OR REPLACE PROCEDURE ATLAS_PLATFORM.PUBLIC.SP_BUILD_CUSTOMER_SEGMENTS()
RETURNS STRING
LANGUAGE SQL
AS
$$
DECLARE
    v_rows_inserted  INT := 0;
    v_start_ts       TIMESTAMP := CURRENT_TIMESTAMP();

    -- Segmentation thresholds (hardcoded — no config table)
    v_vip_threshold      FLOAT := 2000.0;   -- lifetime net revenue
    v_premium_threshold  FLOAT := 800.0;
    v_regular_threshold  FLOAT := 200.0;

    -- Lifecycle thresholds (days since last order)
    v_active_days        INT := 90;
    v_at_risk_days       INT := 180;

BEGIN

    -- -------------------------------------------------------------------------
    -- STEP 1: Pull all raw customers
    -- -------------------------------------------------------------------------
    CREATE OR REPLACE TEMPORARY TABLE tmp_customers AS
    SELECT
        customer_id,
        full_name,
        email,
        acquisition_channel,
        acquisition_date,
        DATE_TRUNC('month', acquisition_date)       AS acquisition_month,
        QUARTER(acquisition_date)                   AS acquisition_quarter,
        YEAR(acquisition_date)                      AS acquisition_year,
        customer_segment                            AS raw_segment
    FROM ATLAS_PLATFORM.RAW.RAW_CUSTOMERS;


    -- -------------------------------------------------------------------------
    -- STEP 2: Calculate order statistics per customer
    -- NOTE: Joins directly to raw tables — no staging layer.
    --       If raw schema changes, this breaks silently.
    -- -------------------------------------------------------------------------
    CREATE OR REPLACE TEMPORARY TABLE tmp_order_stats AS
    SELECT
        o.customer_id,
        COUNT(*)                                        AS total_orders,
        COUNT(CASE WHEN o.order_status = 'COMPLETED' THEN 1 END)
                                                        AS completed_orders,
        SUM(CASE WHEN o.order_status = 'COMPLETED' THEN o.gross_revenue ELSE 0 END)
                                                        AS lifetime_gross_revenue,
        SUM(CASE WHEN o.order_status = 'COMPLETED' THEN o.net_revenue ELSE 0 END)
                                                        AS lifetime_net_revenue,
        AVG(CASE WHEN o.order_status = 'COMPLETED' THEN o.gross_revenue END)
                                                        AS avg_order_value,
        MIN(o.order_date)                               AS first_order_date,
        MAX(o.order_date)                               AS last_order_date,
        DATEDIFF('day', MIN(o.order_date), MAX(o.order_date))
                                                        AS days_between_first_last_order
    FROM ATLAS_PLATFORM.RAW.RAW_ORDERS o
    WHERE o.order_status IN ('COMPLETED', 'RETURNED', 'CANCELLED')
    GROUP BY 1;


    -- -------------------------------------------------------------------------
    -- STEP 3: Assign value tier based on lifetime net revenue
    -- Thresholds are duplicated here from the DECLARE block because
    -- Snowflake SQL stored procedures don't support variable references
    -- inside CASE expressions easily — so values are hardcoded again below.
    -- -------------------------------------------------------------------------
    CREATE OR REPLACE TEMPORARY TABLE tmp_customer_enriched AS
    SELECT
        c.customer_id,
        c.full_name,
        c.email,
        c.acquisition_channel,
        c.acquisition_date,
        c.acquisition_month,
        c.acquisition_quarter,
        c.acquisition_year,

        -- Order metrics
        COALESCE(o.total_orders, 0)                     AS total_orders,
        COALESCE(o.completed_orders, 0)                 AS completed_orders,
        COALESCE(o.lifetime_gross_revenue, 0)           AS lifetime_gross_revenue,
        COALESCE(o.lifetime_net_revenue, 0)             AS lifetime_net_revenue,
        COALESCE(o.avg_order_value, 0)                  AS avg_order_value,
        o.first_order_date,
        o.last_order_date,
        DATEDIFF('day', c.acquisition_date, CURRENT_DATE())
                                                        AS days_since_acquisition,
        -- BUG 1: operands are flipped — produces negative values,
        -- so every customer passes the <= 90 check and is marked "active"
        DATEDIFF('day', CURRENT_DATE(), o.last_order_date)
                                                        AS days_since_last_order,

        -- BUG 2: VIP threshold was raised to $2,500 in Q4 planning
        -- but was never updated here — ~400 customers are mis-tiered
        CASE
            WHEN COALESCE(o.lifetime_net_revenue, 0) >= 2000 THEN 'VIP'
            WHEN COALESCE(o.lifetime_net_revenue, 0) >= 800  THEN 'Premium'
            WHEN COALESCE(o.lifetime_net_revenue, 0) >= 200  THEN 'Regular'
            ELSE 'Budget'
        END                                             AS customer_value_tier,

        -- BUG 3: lifecycle stage uses the bugged days_since_last_order above —
        -- all customers with any order will be classified as "active"
        -- because negative days always satisfies <= 90
        CASE
            WHEN o.last_order_date IS NULL
                THEN 'never_purchased'
            WHEN DATEDIFF('day', CURRENT_DATE(), o.last_order_date) <= 90
                THEN 'active'
            WHEN DATEDIFF('day', CURRENT_DATE(), o.last_order_date) <= 180
                THEN 'at_risk'
            ELSE 'churned'
        END                                             AS customer_lifecycle_stage,

        -- BUG 4: copies raw_segment directly with no validation —
        -- NULL and unexpected values (e.g. 'n/a', 'unknown') pass through silently
        c.raw_segment                                   AS customer_segment

    FROM tmp_customers c
    LEFT JOIN tmp_order_stats o ON c.customer_id = o.customer_id;


    -- -------------------------------------------------------------------------
    -- STEP 4: Truncate and reload DIM_CUSTOMERS
    -- Full refresh every night — expensive on large tables.
    -- No merge key, no incremental logic, no history tracking.
    -- -------------------------------------------------------------------------
    TRUNCATE TABLE IF EXISTS ATLAS_PLATFORM.PUBLIC.DIM_CUSTOMERS;

    CREATE TABLE IF NOT EXISTS ATLAS_PLATFORM.PUBLIC.DIM_CUSTOMERS AS
    SELECT * FROM tmp_customer_enriched WHERE 1 = 0;

    INSERT INTO ATLAS_PLATFORM.PUBLIC.DIM_CUSTOMERS
    SELECT * FROM tmp_customer_enriched;

    v_rows_inserted := SQLROWCOUNT;


    -- -------------------------------------------------------------------------
    -- STEP 5: Basic row count check (no column-level tests)
    -- -------------------------------------------------------------------------
    IF (v_rows_inserted = 0) THEN
        RETURN 'WARNING — 0 rows inserted. Check source tables.';
    END IF;


    -- -------------------------------------------------------------------------
    -- STEP 6: Log execution
    -- -------------------------------------------------------------------------
    INSERT INTO ATLAS_PLATFORM.PUBLIC.SP_EXECUTION_LOG
        (procedure_name, start_ts, end_ts, rows_affected, status, params)
    VALUES (
        'SP_BUILD_CUSTOMER_SEGMENTS',
        :v_start_ts,
        CURRENT_TIMESTAMP(),
        :v_rows_inserted,
        'SUCCESS',
        'full_refresh'
    );

    RETURN 'SUCCESS — ' || :v_rows_inserted || ' customers processed.';

EXCEPTION
    WHEN OTHER THEN
        INSERT INTO ATLAS_PLATFORM.PUBLIC.SP_EXECUTION_LOG
            (procedure_name, start_ts, end_ts, rows_affected, status, params)
        VALUES (
            'SP_BUILD_CUSTOMER_SEGMENTS',
            :v_start_ts,
            CURRENT_TIMESTAMP(),
            0,
            'FAILED: ' || SQLERRM,
            'full_refresh'
        );
        RETURN 'FAILED: ' || SQLERRM;

END;
$$;


-- =============================================================================
-- Usage
-- =============================================================================
-- Run:
--   CALL ATLAS_PLATFORM.PUBLIC.SP_BUILD_CUSTOMER_SEGMENTS();
--
-- Query results:
--   SELECT customer_value_tier, customer_lifecycle_stage,
--          COUNT(*) AS customers,
--          SUM(lifetime_net_revenue) AS total_ltv
--   FROM ATLAS_PLATFORM.PUBLIC.DIM_CUSTOMERS
--   GROUP BY 1, 2
--   ORDER BY 1, 2;
-- =============================================================================
