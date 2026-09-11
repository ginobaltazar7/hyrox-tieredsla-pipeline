{{ config(materialized='table') }}
SELECT * FROM {{ ref('stg_hyrox_races') }}
