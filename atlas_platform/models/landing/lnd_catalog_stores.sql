-- Landing passthrough of the catalog_stores seed. Stands in for Fivetran landing raw data in the lake.
-- Lake Compute mode: Snowflake writes it as an Iceberg table so Lake Compute can read it.
-- Otherwise ephemeral: no object is created and the compiled SQL is unchanged.
select * from {{ ref('catalog_stores') }}
