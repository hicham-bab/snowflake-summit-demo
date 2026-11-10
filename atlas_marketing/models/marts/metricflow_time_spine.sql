{{ config(materialized='view', schema='marts_marketing') }}

-- MetricFlow time spine for this project, one row per day, from the platform's public dim_dates.
select date_day
from {{ ref('atlas_platform', 'dim_dates') }}
