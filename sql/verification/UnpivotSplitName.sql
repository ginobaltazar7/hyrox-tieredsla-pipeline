-- sql/verification/UnpivotSplitName.sql
--
-- What it is: the hand-SQL computation of per-station transition-time
-- variance for the elite/pro divisions — the UNPIVOT behind the Q1
-- numbers (Sled Pull 6.70, Wall Balls 5.61, and so on). The same logic
-- lives in dbt_project/models/gold_marketing/q1_station_long.sql and
-- q1_station_variance.sql; this file is the Snowflake-native version
-- and the cross-check.

SELECT
  split_name AS station,
  COUNT(*) AS n_obs,
  ROUND(AVG(split_time), 2) AS avg_station_time,
  ROUND(VARIANCE(split_time), 2) AS var_station_time
FROM SPORTS_ANALYTICS_DB.RAW_BRONZE.pacing_obt
UNPIVOT(split_time FOR split_name IN (
  skierg_time, sledpush_time, sledpull_time,
  burpeebroadjump_time, rowerg_time, farmerscarry_time,
  sandbaglunges_time, wallballs_time
))
WHERE division IN ('pro', 'pro_doubles', 'elite', 'elite_doubles')
GROUP BY split_name
ORDER BY var_station_time DESC;
