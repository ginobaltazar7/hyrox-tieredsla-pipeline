-- sql/verification/q2_station_time_degradation.sql
--
-- What it is: the hand-SQL derivation of the Q2 numbers — first-km deviation
-- (run1 minus the athlete's own mean of runs 1-8) and station degradation
-- (Wallballs minus SkiErg) — per division and pooled. This is the query
-- the frozen Q2 results were worked out in before the dbt models existed.
-- The same derivation lives in substance in
-- dbt_project/models/gold_marketing/q2_station_degradation.sql and
-- q2_deviation_correlation.sql; this file is the Snowflake-native version
-- and the cross-check.

WITH base AS (
  SELECT
    result_id,
    division,
    run1_time - (run1_time + run2_time + run3_time + run4_time
      + run5_time + run6_time + run7_time + run8_time) / 8
      AS first_km_deviation,
    wallballs_time - skierg_time AS station_degradation
  FROM SPORTS_ANALYTICS_DB.RAW_BRONZE.pacing_obt
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
)
-- Per division first, as agreed:
SELECT
  division,
  COUNT(*) AS n,
  AVG(first_km_deviation) AS avg_deviation,
  AVG(station_degradation) AS avg_degradation,
  CORR(first_km_deviation, station_degradation) AS corr_dev_vs_degradation
FROM base
GROUP BY division
ORDER BY division;

-- Pooled check, second:
SELECT
  COUNT(*) AS n,
  CORR(first_km_deviation, station_degradation) AS corr_dev_vs_degradation
FROM base;
