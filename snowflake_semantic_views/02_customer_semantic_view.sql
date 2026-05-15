/*
  Snowflake Semantic View — Customer Context
  ===========================================
  Exposes customer dimension and LTV data to Cortex Analyst.
  Enables natural-language queries like:
    "Which customer segments have the highest 12-month predicted LTV?"
    "Show me active customers in the Northeast by acquisition channel"
    "What percentage of VIP customers are at risk of churn?"
*/

USE DATABASE ATLAS_PLATFORM;
USE SCHEMA MARTS_CORE;

CREATE OR REPLACE SEMANTIC VIEW ATLAS_PLATFORM.MARTS_CORE.CUSTOMER_SEMANTIC_VIEW
  COMMENT = 'Customer dimension + lifetime value context for Cortex Analyst'

  TABLES (
    ATLAS_PLATFORM.MARTS_CORE.DIM_CUSTOMERS AS customers (
      PRIMARY KEY (customer_id)

      DIMENSIONS (
        full_name                 LABEL = 'Customer Name',
        email                     LABEL = 'Email',
        city                      LABEL = 'City',
        state                     LABEL = 'State',
        customer_segment          LABEL = 'Segment'
                                  COMMENT = 'VIP | Premium | Regular | Budget',
        customer_lifecycle_stage  LABEL = 'Lifecycle Stage'
                                  COMMENT = 'active | at_risk | churned | never_purchased',
        customer_value_tier       LABEL = 'Value Tier'
                                  COMMENT = 'high_value | mid_value | low_value | no_purchases',
        acquisition_channel       LABEL = 'Acquisition Channel',
        acquisition_date          LABEL = 'Acquisition Date',
        acquisition_month         LABEL = 'Acquisition Month',
        acquisition_year          LABEL = 'Acquisition Year',
        gender                    LABEL = 'Gender',
        is_email_subscribed       LABEL = 'Email Subscriber',
        is_sms_subscribed         LABEL = 'SMS Subscriber',
        most_common_channel       LABEL = 'Preferred Channel'
      )

      FACTS (
        lifetime_gross_revenue      LABEL = 'Lifetime Gross Revenue',
        lifetime_net_revenue        LABEL = 'Lifetime Net Revenue',
        avg_order_value             LABEL = 'Average Order Value',
        total_orders                LABEL = 'Total Orders',
        completed_orders            LABEL = 'Completed Orders',
        returned_orders             LABEL = 'Returned Orders',
        days_since_acquisition      LABEL = 'Days Since Acquisition'
      )

      MEASURES (
        total_customers             LABEL = 'Total Customers'
                                    AS COUNT(customer_id),

        active_customers            LABEL = 'Active Customers'
                                    COMMENT = 'Customers who ordered in the past 90 days'
                                    AS COUNT_IF(customer_lifecycle_stage = 'active'),

        at_risk_customers           LABEL = 'At-Risk Customers'
                                    AS COUNT_IF(customer_lifecycle_stage = 'at_risk'),

        churned_customers           LABEL = 'Churned Customers'
                                    AS COUNT_IF(customer_lifecycle_stage = 'churned'),

        avg_lifetime_revenue        LABEL = 'Avg Customer LTV'
                                    AS AVG(lifetime_net_revenue),

        total_lifetime_revenue      LABEL = 'Total Customer LTV'
                                    AS SUM(lifetime_net_revenue),

        avg_orders_per_customer     LABEL = 'Avg Orders per Customer'
                                    AS AVG(total_orders),

        active_rate                 LABEL = 'Active Customer Rate %'
                                    AS COUNT_IF(customer_lifecycle_stage = 'active')::FLOAT
                                       / NULLIF(COUNT(customer_id), 0) * 100
      )
    ),

    ATLAS_PLATFORM.MARTS_CORE.FCT_ORDERS AS customer_orders (
      PRIMARY KEY (order_id)

      DIMENSIONS (
        order_status    LABEL = 'Order Status',
        store_channel   LABEL = 'Channel',
        store_region    LABEL = 'Region',
        order_month     LABEL = 'Order Month',
        order_year      LABEL = 'Year'
      )

      FACTS (
        gross_revenue   LABEL = 'Gross Revenue',
        net_revenue     LABEL = 'Net Revenue'
      )

      MEASURES (
        customer_order_count    LABEL = 'Orders'     AS COUNT(order_id),
        customer_revenue        LABEL = 'Revenue'    AS SUM(net_revenue)
      )
    )
  )

  RELATIONSHIPS (
    customer_orders (customer_id) MANY TO ONE customers (customer_id)
  );
