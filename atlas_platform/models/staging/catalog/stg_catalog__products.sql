-- Passthrough of the catalog_products seed. Seeds are plain Snowflake tables, which Lake Compute
-- cannot read, so in Lake Compute mode this is written as a Snowflake-managed Iceberg table.
select * from {{ ref('catalog_products') }}
