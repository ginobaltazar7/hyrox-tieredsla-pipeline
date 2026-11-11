-- sql/verification/LocationEventNullCheck.sql
--
-- What it is: the evidence behind Q3 being blocked — how many of the
-- 5,000 rows actually carry a location and an event name, and how many
-- sit at NULL. Location is enriched for only 58 of 5,000 rows, so there
-- is no honest location answer from this sample yet. Keep this file as
-- the record of that check, not as code to run in production.

SELECT
  COUNT(*) AS n_results,
  COUNT(location) AS n_with_location,
  SUM(case when location is null then 1 else 0 end) as n_null_location,
  COUNT(event_name) AS n_with_event_name,
  sum(case when event_name is null then 1 else 0 end) as n_null_event_name
FROM SPORTS_ANALYTICS_DB.RAW_BRONZE.pacing_obt;
