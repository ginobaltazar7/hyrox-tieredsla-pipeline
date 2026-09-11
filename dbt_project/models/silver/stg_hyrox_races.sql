{{ config(materialized='incremental') }}
SELECT 
    athlete_id,
    name,
    season,
    location,
    total_time_minutes,
    division
FROM {{ source('raw_bronze', 'hyrox_raw_season_8') }}
