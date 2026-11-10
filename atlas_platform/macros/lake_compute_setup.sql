{#- One-off setup for Lake Compute mode: Snowflake registers Lake Compute output as Iceberg
    tables through the Fivetran catalog, which needs an external volume on each target schema.
    Scoped to the *_LC schemas only.
    dbt run-operation lake_compute_setup --target lc -#}
{% macro lake_compute_setup() %}
    {% set volume = env_var('LAKE_COMPUTE_EXTERNAL_VOLUME', 'FIVETRAN_MDLS_TR_VOLUME') %}
    {% for custom in ['staging_ecommerce', 'staging_marketing', 'intermediate', 'marts_core'] %}
        {% set fq = target.database ~ "." ~ generate_schema_name(custom, none) %}
        {% do run_query("create schema if not exists " ~ fq) %}
        {% do run_query("alter schema " ~ fq ~ " set external_volume = '" ~ volume ~ "'") %}
        {{ log("external_volume " ~ volume ~ " set on " ~ fq, info=true) }}
    {% endfor %}
{% endmacro %}
