{% macro generate_schema_name(custom_schema_name, node) -%}

    {%- set default_schema = target.schema -%}

    {%- if custom_schema_name is none -%}

        {{ default_schema }}

    {%- else -%}

        {#-
          Always use the custom schema name without target prefix so that
          cross-project sources (atlas_marketing, atlas_finance) can resolve
          raw/staging/mart schemas consistently across dev and prod.
        -#}
        {{ custom_schema_name | trim }}

    {%- endif -%}

{%- endmacro %}
