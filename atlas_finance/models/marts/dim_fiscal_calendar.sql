{{
    config(
        materialized='table',
        schema='marts_finance',
        tags=['mart', 'finance']
    )
}}

/*
  Materialization: TABLE — Atlas's fiscal calendar (Feb 1 – Jan 31).
  Derived from the platform's dim_dates and enriched with finance-specific
  period labels for budget vs. actuals alignment.
*/

WITH dates AS (
    SELECT * FROM {{ ref('atlas_platform', 'dim_dates') }}
    WHERE year_num BETWEEN 2025 AND 2027
),

fiscal AS (
    SELECT
        date_day,
        fiscal_year,
        fiscal_quarter,
        fiscal_month,

        -- Fiscal labels
        'FY' || fiscal_year                             AS fiscal_year_label,
        'FY' || fiscal_year || '-Q' || fiscal_quarter   AS fiscal_quarter_label,
        'FY' || fiscal_year || '-P' || LPAD(fiscal_month::VARCHAR, 2, '0')
                                                        AS fiscal_period_label,

        -- Is the date in the current fiscal year?
        fiscal_year = (
            CASE
                WHEN MONTH(CURRENT_DATE()) >= 2 THEN YEAR(CURRENT_DATE())
                ELSE YEAR(CURRENT_DATE()) - 1
            END
        )                                               AS is_current_fiscal_year,

        fiscal_quarter = (
            CASE
                WHEN MONTH(CURRENT_DATE()) >= 2
                THEN CEIL((MONTH(CURRENT_DATE()) - 1)::FLOAT / 3)
                ELSE 4
            END
        ) AND fiscal_year = (
            CASE
                WHEN MONTH(CURRENT_DATE()) >= 2 THEN YEAR(CURRENT_DATE())
                ELSE YEAR(CURRENT_DATE()) - 1
            END
        )                                               AS is_current_fiscal_quarter,

        -- Reporting periods for budget comparison
        DATE_TRUNC('month',
            CASE
                WHEN MONTH(date_day) >= 2
                THEN DATEADD('month', -(MONTH(date_day) - 2), DATE_TRUNC('month', date_day))
                ELSE DATEADD('month', 10, DATE_TRUNC('month', date_day))
            END
        )                                               AS fiscal_period_start,

        -- Standard calendar passthrough
        MONTH(date_day)                                 AS calendar_month,
        QUARTER(date_day)                               AS calendar_quarter,
        YEAR(date_day)                                  AS calendar_year,
        is_weekend,
        is_weekday,
        season

    FROM dates
)

SELECT * FROM fiscal
