/*
  Snowflake Semantic View — Revenue Context
  ==========================================
  Defines semantic metadata directly in Snowflake for the Cortex Analyst
  and other Snowflake AI features. Complements the dbt Semantic Layer:
    - dbt Semantic Layer = governed metrics via MetricFlow API
    - Snowflake Semantic Views = native Snowflake context for Cortex SQL generation

  Run this after dbt build completes to register semantic context in Snowflake.
  Requires: ACCOUNTADMIN or SYSADMIN role with CREATE SEMANTIC VIEW privilege.
*/

USE DATABASE ATLAS_PLATFORM;
USE SCHEMA MARTS_CORE;

CREATE OR REPLACE SEMANTIC VIEW ATLAS_PLATFORM.MARTS_CORE.REVENUE_SEMANTIC_VIEW
  COMMENT = 'Revenue and order metrics for Atlas Commerce — powers Cortex Analyst queries'

  TABLES (
    ATLAS_PLATFORM.MARTS_CORE.FCT_ORDERS AS orders (
      PRIMARY KEY (order_id)

      UNIQUE KEY (order_id)

      DIMENSIONS (
        order_date              LABEL = 'Order Date'
                                COMMENT = 'Calendar date the order was placed',
        order_month             LABEL = 'Order Month',
        order_quarter           LABEL = 'Quarter',
        order_year              LABEL = 'Year',
        order_status            LABEL = 'Order Status'
                                COMMENT = 'COMPLETED | RETURNED | CANCELLED',
        store_channel           LABEL = 'Channel'
                                COMMENT = 'in-store | online | mobile',
        store_region            LABEL = 'Region'
                                COMMENT = 'Geographic region of the fulfilling store',
        store_city              LABEL = 'Store City',
        store_state             LABEL = 'Store State',
        traffic_source          LABEL = 'Traffic Source'
                                COMMENT = 'paid_search | paid_social | organic | email | direct | affiliate',
        payment_method          LABEL = 'Payment Method',
        has_discount            LABEL = 'Has Discount',
        is_completed            LABEL = 'Is Completed',
        is_returned             LABEL = 'Is Returned'
      )

      FACTS (
        gross_revenue           LABEL = 'Gross Revenue'
                                COMMENT = 'Revenue before discounts and returns',
        net_revenue             LABEL = 'Net Revenue'
                                COMMENT = 'Gross revenue minus order-level discounts',
        realized_revenue        LABEL = 'Realized Revenue'
                                COMMENT = 'Net revenue minus approved refunds — cash collected',
        order_level_discount    LABEL = 'Discount Amount',
        refund_amount           LABEL = 'Refund Amount'
                                COMMENT = 'Approved refund applied to returned orders',
        estimated_tax           LABEL = 'Estimated Tax',
        total_units             LABEL = 'Units Sold',
        item_count              LABEL = 'Line Items'
      )

      MEASURES (
        total_gross_revenue     LABEL = 'Total Gross Revenue'
                                COMMENT = 'Sum of gross revenue across all orders'
                                AS SUM(gross_revenue),

        total_net_revenue       LABEL = 'Total Net Revenue'
                                AS SUM(net_revenue),

        total_realized_revenue  LABEL = 'Total Realized Revenue'
                                AS SUM(realized_revenue),

        total_orders            LABEL = 'Total Orders'
                                AS COUNT(order_id),

        completed_orders        LABEL = 'Completed Orders'
                                AS COUNT_IF(is_completed),

        average_order_value     LABEL = 'Average Order Value (AOV)'
                                COMMENT = 'Average gross revenue per completed order'
                                AS AVG(CASE WHEN is_completed THEN gross_revenue END),

        total_discounts         LABEL = 'Total Discounts'
                                AS SUM(order_level_discount),

        total_refunds           LABEL = 'Total Refunds'
                                AS SUM(CASE WHEN is_returned THEN refund_amount ELSE 0 END),

        return_rate             LABEL = 'Return Rate %'
                                COMMENT = 'Percentage of orders that were returned'
                                AS COUNT_IF(is_returned)::FLOAT / NULLIF(COUNT(order_id), 0) * 100
      )
    ),

    ATLAS_PLATFORM.MARTS_CORE.DIM_STORES AS stores (
      PRIMARY KEY (store_id)

      DIMENSIONS (
        store_name    LABEL = 'Store Name',
        store_type    LABEL = 'Store Type'    COMMENT = 'physical | digital',
        channel       LABEL = 'Channel',
        city          LABEL = 'City',
        state         LABEL = 'State',
        region        LABEL = 'Region',
        district      LABEL = 'District',
        opened_date   LABEL = 'Opened Date'
      )
    ),

    ATLAS_PLATFORM.MARTS_CORE.DIM_DATES AS dates (
      PRIMARY KEY (date_day)

      DIMENSIONS (
        date_day          LABEL = 'Date',
        day_of_week_name  LABEL = 'Day of Week',
        month_name        LABEL = 'Month',
        quarter_name      LABEL = 'Quarter',
        year_num          LABEL = 'Year',
        fiscal_year       LABEL = 'Fiscal Year'   COMMENT = 'Atlas fiscal year runs Feb 1 – Jan 31',
        fiscal_quarter    LABEL = 'Fiscal Quarter',
        season            LABEL = 'Season',
        is_weekend        LABEL = 'Is Weekend',
        is_black_friday   LABEL = 'Is Black Friday',
        is_cyber_monday   LABEL = 'Is Cyber Monday'
      )
    )
  )

  RELATIONSHIPS (
    orders (store_id)   MANY TO ONE stores (store_id),
    orders (order_date) MANY TO ONE dates  (date_day)
  );

-- Verify creation
SHOW SEMANTIC VIEWS IN SCHEMA ATLAS_PLATFORM.MARTS_CORE;
