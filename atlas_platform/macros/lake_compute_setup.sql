{#- One-off setup for Lake Compute mode: Snowflake registers Lake Compute output as Iceberg
    tables, which needs an external volume on the target schema. Scoped to *_LC schemas only.
    dbt run-operation lake_compute_setup --target lc -#}
{% macro lake_compute_setup() %}
    {% set schema = generate_schema_name('intermediate', none) %}
    {% do run_query("create schema if not exists " ~ target.database ~ "." ~ schema) %}
    {% do run_query("alter schema " ~ target.database ~ "." ~ schema ~ " set external_volume = '" ~ env_var('LAKE_COMPUTE_EXTERNAL_VOLUME', 'FIVETRAN_MDLS_TR_VOLUME') ~ "'") %}
    {{ log("external_volume set on " ~ target.database ~ "." ~ schema, info=true) }}
{% endmacro %}
