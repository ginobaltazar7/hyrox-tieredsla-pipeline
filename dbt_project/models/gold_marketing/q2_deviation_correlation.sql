{{ config(materialized='table') }}
SELECT
  division,
  COUNT(*) AS n,
  AVG(first_km_deviation) AS avg_deviation,
  AVG(station_degradation) AS avg_degradation,
  CORR(first_km_deviation, station_degradation) AS corr_dev_vs_degradation
FROM {{ ref('q2_station_degradation') }}
GROUP BY division

UNION ALL

SELECT
  'ALL' AS division,
  COUNT(*) AS n,
  AVG(first_km_deviation) AS avg_deviation,
  AVG(station_degradation) AS avg_degradation,
  CORR(first_km_deviation, station_degradation) AS corr_dev_vs_degradation
FROM {{ ref('q2_station_degradation') }}
ORDER BY division
