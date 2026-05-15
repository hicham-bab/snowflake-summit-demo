{{
    config(
        materialized='table',
        schema='marts_core',
        tags=['mart', 'core', 'published'],
        access='public'
    )
}}

/*
  Materialization: TABLE — date spine covering 2022-01-01 through 2027-12-31.
  Published as a public Mesh node for consistent fiscal calendar logic across projects.
  Atlas's fiscal year runs Feb 1 – Jan 31.
*/

WITH date_spine AS (
    SELECT
        DATEADD('day', seq4(), '2022-01-01'::DATE) AS date_day
    FROM TABLE(GENERATOR(ROWCOUNT => 2192))  -- 6 years
),

dates AS (
    SELECT
        date_day,

        -- Standard calendar
        DAYOFWEEK(date_day)                             AS day_of_week_num,  -- 0=Sun
        DAYNAME(date_day)                               AS day_of_week_name,
        DAY(date_day)                                   AS day_of_month,
        DAYOFYEAR(date_day)                             AS day_of_year,
        WEEK(date_day)                                  AS week_of_year,
        DATE_TRUNC('week',  date_day)                   AS week_start_date,
        MONTH(date_day)                                 AS month_num,
        MONTHNAME(date_day)                             AS month_name,
        DATE_TRUNC('month', date_day)                   AS month_start_date,
        QUARTER(date_day)                               AS quarter_num,
        'Q' || QUARTER(date_day)                        AS quarter_name,
        DATE_TRUNC('quarter', date_day)                 AS quarter_start_date,
        YEAR(date_day)                                  AS year_num,

        -- Weekend / weekday
        DAYOFWEEK(date_day) IN (0, 6)                  AS is_weekend,
        DAYOFWEEK(date_day) NOT IN (0, 6)              AS is_weekday,

        -- Atlas fiscal calendar (Feb 1 – Jan 31)
        CASE
            WHEN MONTH(date_day) >= 2 THEN YEAR(date_day)
            ELSE YEAR(date_day) - 1
        END                                             AS fiscal_year,

        CASE
            WHEN MONTH(date_day) >= 2
            THEN CEIL((MONTH(date_day) - 1)::FLOAT / 3)
            ELSE 4
        END                                             AS fiscal_quarter,

        CASE
            WHEN MONTH(date_day) >= 2 THEN MONTH(date_day) - 1
            ELSE MONTH(date_day) + 11
        END                                             AS fiscal_month,

        -- Holiday flags (US retail key dates)
        CASE
            WHEN MONTH(date_day) = 11 AND date_day =
                -- Black Friday: 4th Thursday of November + 1
                DATEADD('day', 1,
                    DATEADD('day',
                        (5 - DAYOFWEEK(DATE_TRUNC('month', date_day))) % 7 + 21,
                        DATE_TRUNC('month', date_day)
                    )
                )
            THEN TRUE ELSE FALSE
        END                                             AS is_black_friday,

        MONTH(date_day) = 12 AND DAY(date_day) = 1    AS is_cyber_monday,
        MONTH(date_day) = 12 AND DAY(date_day) = 25   AS is_christmas,
        MONTH(date_day) = 1  AND DAY(date_day) = 1    AS is_new_years,
        MONTH(date_day) = 7  AND DAY(date_day) = 4    AS is_independence_day,
        MONTH(date_day) = 2  AND DAY(date_day) = 14   AS is_valentines_day,

        -- Season
        CASE
            WHEN MONTH(date_day) IN (12, 1, 2) THEN 'Winter'
            WHEN MONTH(date_day) IN (3, 4, 5)  THEN 'Spring'
            WHEN MONTH(date_day) IN (6, 7, 8)  THEN 'Summer'
            ELSE 'Fall'
        END                                             AS season

    FROM date_spine
)

SELECT * FROM dates
