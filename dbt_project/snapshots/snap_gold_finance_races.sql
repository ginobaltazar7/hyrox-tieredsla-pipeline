{% snapshot snap_gold_finance_races %}

{{
    config(
        target_schema='gold_finance',
        unique_key='athlete_id',
        strategy='timestamp',
        updated_at='updated_at',
        invalidate_hard_deletes=true
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
FROM {{ ref('stg_hyrox_races') }}

{% endsnapshot %}