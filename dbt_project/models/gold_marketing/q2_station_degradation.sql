{{ config(materialized='table') }}
SELECT
  result_id,
  division,
  to_date('2020-01-01', 'YYYY-MM-DD') AS pacing_date,
  run1_time - (run1_time + run2_time + run3_time + run4_time
    + run5_time + run6_time + run7_time + run8_time) / 8
    AS first_km_deviation,
  wallballs_time - skierg_time AS station_degradation
FROM {{ ref('pacing_obt') }}
WHERE run1_time IS NOT NULL
  AND run2_time IS NOT NULL
  AND run3_time IS NOT NULL
  AND run4_time IS NOT NULL
  AND run5_time IS NOT NULL
  AND run6_time IS NOT NULL
  AND run7_time IS NOT NULL
  AND run8_time IS NOT NULL
  AND skierg_time IS NOT NULL
  AND wallballs_time IS NOT NULL