/*
  Snowflake Semantic View — Marketing Performance Context
  =======================================================
  Exposes campaign spend, ROAS, and attribution data to Cortex Analyst.
  Enables natural-language queries like:
    "Which campaign had the highest ROAS in Q4 2025?"
    "Compare paid social vs paid search cost-per-acquisition last quarter"
    "Show me spend efficiency by channel over the past 6 months"

  Run in ATLAS_MARKETING database after dbt build.
*/

USE DATABASE ATLAS_MARKETING;
USE SCHEMA MARTS_MARKETING;

CREATE OR REPLACE SEMANTIC VIEW ATLAS_MARKETING.MARTS_MARKETING.MARKETING_SEMANTIC_VIEW
  COMMENT = 'Campaign performance and attribution context for Cortex Analyst'

  TABLES (
    ATLAS_MARKETING.MARTS_MARKETING.FCT_CAMPAIGN_PERFORMANCE AS campaigns (
      PRIMARY KEY (campaign_id, spend_date)

      DIMENSIONS (
        campaign_id     LABEL = 'Campaign ID',
        campaign_name   LABEL = 'Campaign Name',
        channel         LABEL = 'Channel'
                        COMMENT = 'paid_social | paid_search | email | affiliate',
        campaign_type   LABEL = 'Campaign Type'
                        COMMENT = 'awareness | conversion | retention | brand | partnership',
        spend_date      LABEL = 'Spend Date',
        spend_month     LABEL = 'Spend Month',
        spend_quarter   LABEL = 'Quarter',
        spend_year      LABEL = 'Year',
        roas_tier       LABEL = 'ROAS Tier'
                        COMMENT = 'high_performing | efficient | break_even | underperforming'
      )

      FACTS (
        spend_usd               LABEL = 'Ad Spend ($)',
        impressions             LABEL = 'Impressions',
        clicks                  LABEL = 'Clicks',
        attributed_net_revenue  LABEL = 'Attributed Revenue',
        dbt_attributed_orders   LABEL = 'Attributed Orders',
        roas                    LABEL = 'ROAS',
        click_through_rate_pct  LABEL = 'CTR %',
        cost_per_click          LABEL = 'CPC',
        cost_per_acquisition    LABEL = 'CPA'
      )

      MEASURES (
        total_spend             LABEL = 'Total Ad Spend'
                                AS SUM(spend_usd),

        total_impressions       LABEL = 'Total Impressions'
                                AS SUM(impressions),

        total_clicks            LABEL = 'Total Clicks'
                                AS SUM(clicks),

        total_attributed_revenue LABEL = 'Total Attributed Revenue'
                                AS SUM(attributed_net_revenue),

        total_attributed_orders LABEL = 'Total Attributed Orders'
                                AS SUM(dbt_attributed_orders),

        blended_roas            LABEL = 'Blended ROAS'
                                COMMENT = 'Return on ad spend — attributed revenue / total spend'
                                AS SUM(attributed_net_revenue)::FLOAT
                                   / NULLIF(SUM(spend_usd), 0),

        avg_ctr                 LABEL = 'Avg CTR %'
                                AS AVG(click_through_rate_pct),

        avg_cpa                 LABEL = 'Avg CPA'
                                AS AVG(cost_per_acquisition),

        high_performing_days    LABEL = 'High-Performing Days'
                                AS COUNT_IF(roas_tier = 'high_performing')
      )
    ),

    ATLAS_MARKETING.MARTS_MARKETING.FCT_CHANNEL_ATTRIBUTION AS attribution (
      PRIMARY KEY (attributed_channel, order_month)

      DIMENSIONS (
        attributed_channel  LABEL = 'Channel',
        order_month         LABEL = 'Month'
      )

      FACTS (
        attributed_net_revenue  LABEL = 'Attributed Revenue',
        attributed_orders       LABEL = 'Attributed Orders',
        mobile_revenue          LABEL = 'Mobile Revenue',
        mobile_revenue_pct      LABEL = 'Mobile Revenue %'
      )

      MEASURES (
        channel_revenue         LABEL = 'Channel Revenue'
                                AS SUM(attributed_net_revenue),

        channel_orders          LABEL = 'Channel Orders'
                                AS SUM(attributed_orders),

        mobile_share            LABEL = 'Mobile Revenue Share %'
                                AS AVG(mobile_revenue_pct)
      )
    )
  )

  RELATIONSHIPS (
    -- No direct FK between these tables; both are analyzed independently
  );
