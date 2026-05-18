-- =============================================================================
-- Stored Procedure: SP_CAMPAIGN_ROI_REPORT
-- Purpose:         Builds a campaign performance summary by joining orders,
--                  ad spend, and campaign metadata. Truncates and reloads
--                  the full result table on every run.
-- Schedule:        Run manually or via task — no incremental logic.
-- Owner:           data-team@atlas.com
-- Last modified:   2025-11-15
-- WARNING:         Hardcoded to ATLAS_PLATFORM database. Change before
--                  running in any other environment.
-- =============================================================================

CREATE OR REPLACE PROCEDURE ATLAS_PLATFORM.PUBLIC.SP_CAMPAIGN_ROI_REPORT(
    P_START_DATE DATE DEFAULT '2025-06-01',
    P_END_DATE   DATE DEFAULT CURRENT_DATE()
)
RETURNS STRING
LANGUAGE SQL
AS
$$
DECLARE
    v_rows_inserted  INT := 0;
    v_start_ts       TIMESTAMP := CURRENT_TIMESTAMP();
BEGIN

    -- -------------------------------------------------------------------------
    -- STEP 1: Stage raw orders within the date window
    -- -------------------------------------------------------------------------
    CREATE OR REPLACE TEMPORARY TABLE tmp_orders AS
    SELECT
        order_id,
        customer_id,
        store_id,
        campaign_id,
        traffic_source,
        order_date,
        order_status,
        gross_revenue,
        net_revenue,
        COALESCE(refund_amount, 0)                          AS refund_amount,
        CASE WHEN order_status = 'COMPLETED' THEN TRUE ELSE FALSE END AS is_completed,
        CASE WHEN order_status = 'RETURNED'  THEN TRUE ELSE FALSE END AS is_returned
    FROM ATLAS_PLATFORM.RAW.RAW_ORDERS
    WHERE order_date BETWEEN :P_START_DATE AND :P_END_DATE
      AND campaign_id IS NOT NULL;


    -- -------------------------------------------------------------------------
    -- STEP 2: Aggregate orders to campaign + day level
    -- -------------------------------------------------------------------------
    CREATE OR REPLACE TEMPORARY TABLE tmp_order_agg AS
    SELECT
        campaign_id,
        order_date,
        COUNT(*)                                            AS total_orders,
        COUNT(CASE WHEN is_completed THEN 1 END)            AS completed_orders,
        COUNT(CASE WHEN is_returned  THEN 1 END)            AS returned_orders,
        SUM(CASE WHEN is_completed THEN gross_revenue ELSE 0 END) AS gross_revenue,
        SUM(CASE WHEN is_completed THEN net_revenue   ELSE 0 END) AS net_revenue,
        SUM(CASE WHEN is_returned  THEN refund_amount ELSE 0 END) AS refund_amount,
        COUNT(DISTINCT customer_id)                         AS unique_customers
    FROM tmp_orders
    GROUP BY 1, 2;


    -- -------------------------------------------------------------------------
    -- STEP 3: Pull ad spend (hardcoded schema — change for other envs)
    -- -------------------------------------------------------------------------
    CREATE OR REPLACE TEMPORARY TABLE tmp_ad_spend AS
    SELECT
        campaign_id,
        spend_date,
        spend_usd,
        impressions,
        clicks,
        attributed_orders                                   AS platform_attributed_orders
    FROM ATLAS_PLATFORM.RAW.RAW_AD_SPEND;


    -- -------------------------------------------------------------------------
    -- STEP 4: Join everything and compute ROI metrics
    -- NOTE: No incremental logic — full truncate + reload every run.
    --       On large datasets this will be slow.
    -- -------------------------------------------------------------------------
    CREATE OR REPLACE TEMPORARY TABLE tmp_campaign_roi AS
    SELECT
        c.campaign_id,
        c.campaign_name,
        c.channel,
        c.campaign_type,
        c.budget_usd                                        AS total_budget,
        c.start_date                                        AS campaign_start,
        c.end_date                                          AS campaign_end,
        c.target_segment,

        -- Date
        COALESCE(sp.spend_date, ord.order_date)             AS report_date,

        -- Spend metrics
        COALESCE(sp.spend_usd, 0)                           AS spend_usd,
        COALESCE(sp.impressions, 0)                         AS impressions,
        COALESCE(sp.clicks, 0)                              AS clicks,

        -- Order metrics
        COALESCE(ord.total_orders, 0)                       AS total_orders,
        COALESCE(ord.completed_orders, 0)                   AS completed_orders,
        COALESCE(ord.returned_orders, 0)                    AS returned_orders,
        COALESCE(ord.gross_revenue, 0)                      AS gross_revenue,
        COALESCE(ord.net_revenue, 0)                        AS net_revenue,
        COALESCE(ord.refund_amount, 0)                      AS refund_amount,
        COALESCE(ord.net_revenue, 0)
            - COALESCE(ord.refund_amount, 0)                AS realized_revenue,
        COALESCE(ord.unique_customers, 0)                   AS unique_customers,

        -- Derived KPIs
        CASE
            WHEN COALESCE(sp.spend_usd, 0) > 0
            THEN ROUND(COALESCE(ord.net_revenue, 0) / sp.spend_usd, 2)
        END                                                 AS roas,

        CASE
            WHEN COALESCE(sp.clicks, 0) > 0
            THEN ROUND(sp.spend_usd / sp.clicks, 2)
        END                                                 AS cost_per_click,

        CASE
            WHEN COALESCE(ord.completed_orders, 0) > 0
            THEN ROUND(sp.spend_usd / ord.completed_orders, 2)
        END                                                 AS cost_per_acquisition,

        CASE
            WHEN COALESCE(sp.impressions, 0) > 0
            THEN ROUND(sp.clicks / sp.impressions * 100, 4)
        END                                                 AS click_through_rate_pct,

        CASE
            WHEN COALESCE(sp.clicks, 0) > 0
            THEN ROUND(ord.completed_orders / sp.clicks * 100, 2)
        END                                                 AS click_to_order_rate_pct,

        CURRENT_TIMESTAMP()                                 AS last_refreshed_at

    FROM ATLAS_PLATFORM.SEEDS.CATALOG_CAMPAIGNS c
    LEFT JOIN tmp_ad_spend sp
        ON  c.campaign_id = sp.campaign_id
    LEFT JOIN tmp_order_agg ord
        ON  c.campaign_id = ord.campaign_id
        AND sp.spend_date  = ord.order_date
    WHERE COALESCE(sp.spend_date, ord.order_date) IS NOT NULL;


    -- -------------------------------------------------------------------------
    -- STEP 5: Truncate target table and reload
    -- (No merge key — full reload every time)
    -- -------------------------------------------------------------------------
    TRUNCATE TABLE IF EXISTS ATLAS_PLATFORM.PUBLIC.CAMPAIGN_ROI_REPORT;

    CREATE TABLE IF NOT EXISTS ATLAS_PLATFORM.PUBLIC.CAMPAIGN_ROI_REPORT AS
    SELECT * FROM tmp_campaign_roi WHERE 1 = 0;

    INSERT INTO ATLAS_PLATFORM.PUBLIC.CAMPAIGN_ROI_REPORT
    SELECT * FROM tmp_campaign_roi;

    v_rows_inserted := SQLROWCOUNT;


    -- -------------------------------------------------------------------------
    -- STEP 6: Log execution
    -- -------------------------------------------------------------------------
    INSERT INTO ATLAS_PLATFORM.PUBLIC.SP_EXECUTION_LOG
        (procedure_name, start_ts, end_ts, rows_affected, status, params)
    VALUES (
        'SP_CAMPAIGN_ROI_REPORT',
        :v_start_ts,
        CURRENT_TIMESTAMP(),
        :v_rows_inserted,
        'SUCCESS',
        'start=' || :P_START_DATE || ', end=' || :P_END_DATE
    );

    RETURN 'SUCCESS — ' || :v_rows_inserted
        || ' rows loaded for '
        || :P_START_DATE || ' → ' || :P_END_DATE;

EXCEPTION
    WHEN OTHER THEN
        INSERT INTO ATLAS_PLATFORM.PUBLIC.SP_EXECUTION_LOG
            (procedure_name, start_ts, end_ts, rows_affected, status, params)
        VALUES (
            'SP_CAMPAIGN_ROI_REPORT',
            :v_start_ts,
            CURRENT_TIMESTAMP(),
            0,
            'FAILED: ' || SQLERRM,
            'start=' || :P_START_DATE || ', end=' || :P_END_DATE
        );
        RETURN 'FAILED: ' || SQLERRM;

END;
$$;


-- =============================================================================
-- Supporting objects
-- =============================================================================

-- Execution log table (must exist before first SP run)
CREATE TABLE IF NOT EXISTS ATLAS_PLATFORM.PUBLIC.SP_EXECUTION_LOG (
    log_id          INT AUTOINCREMENT PRIMARY KEY,
    procedure_name  VARCHAR,
    start_ts        TIMESTAMP,
    end_ts          TIMESTAMP,
    rows_affected   INT,
    status          VARCHAR,
    params          VARCHAR
);


-- =============================================================================
-- Usage
-- =============================================================================
-- Full history:
--   CALL ATLAS_PLATFORM.PUBLIC.SP_CAMPAIGN_ROI_REPORT();
--
-- Custom window:
--   CALL ATLAS_PLATFORM.PUBLIC.SP_CAMPAIGN_ROI_REPORT('2026-01-01', '2026-03-31');
--
-- Query results:
--   SELECT * FROM ATLAS_PLATFORM.PUBLIC.CAMPAIGN_ROI_REPORT
--   ORDER BY report_date DESC, roas DESC NULLS LAST;
-- =============================================================================
