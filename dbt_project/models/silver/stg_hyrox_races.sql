{{ 
    config(
        materialized='incremental',
        unique_key=['athlete_id', 'season'],
        incremental_strategy='merge'
    ) 
}}

SELECT 
    athlete_id,
    name,
    season,
    location,
    total_time_minutes,
    division,
    updated_at
FROM {{ source('raw_bronze', 'hyrox_raw_season_8') }}