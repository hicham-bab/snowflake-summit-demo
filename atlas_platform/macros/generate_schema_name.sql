{% macro generate_schema_name(custom_schema_name, node) -%}

    {%- set default_schema = target.schema -%}
    {#- Lake Compute mode writes to <schema>_LC so it never overwrites the Snowflake-only tables. -#}
    {%- set suffix = '_LC' if env_var('DBT_USE_LAKE_COMPUTE', 'true' if target.name == 'lc' else 'false') | lower == 'true' else '' -%}

    {%- if custom_schema_name is none -%}

        {{ default_schema }}{{ suffix }}

    {%- else -%}

        {#-
          Always use the custom schema name without target prefix so that
          cross-project sources (atlas_marketing, atlas_finance) can resolve
          raw/staging/mart schemas consistently across dev and prod.
        -#}
        {{ custom_schema_name | trim }}{{ suffix }}

    {%- endif -%}

{%- endmacro %}
