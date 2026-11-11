-- sql/verification/Dupchecks.sql
--
-- What it is: the result_id uniqueness check behind Q5 — any result_id
-- appearing more than once in pacing_obt. Companion to
-- DuplicateResults.sql.

SELECT result_id, COUNT(*) AS n_rows
FROM SPORTS_ANALYTICS_DB.RAW_BRONZE.pacing_obt
GROUP BY result_id
HAVING COUNT(*) > 1
ORDER BY n_rows DESC;
