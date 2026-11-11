-- sql/verification/UnknownLocations.sql
--
-- What it is: the distinct locations present in pacing_obt, top 30 —
-- companion to LocationEventNullCheck.sql and part of the evidence that
-- Q3 is blocked (location enriched for only 58 of 5,000 rows; the rest
-- is UNKNOWN, and UNKNOWN is not a place).

SELECT location, COUNT(*) AS n_results
FROM SPORTS_ANALYTICS_DB.RAW_BRONZE.pacing_obt
GROUP BY location
ORDER BY n_results DESC
LIMIT 30;
