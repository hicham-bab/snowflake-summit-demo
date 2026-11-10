-- Landing passthrough of the raw_ad_spend seed. Stands in for Fivetran landing raw data in the lake.
-- Lake Compute mode: Snowflake writes it as an Iceberg table so Lake Compute can read it.
-- Otherwise ephemeral: no object is created and the compiled SQL is unchanged.
select * from {{ ref('raw_ad_spend') }}
