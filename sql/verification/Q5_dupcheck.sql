-- sql/verification/Q5_dupcheck.sql
--
-- What it is: the Q5 registration-audit probe — athletes appearing more
-- than once in the same event, the check that settled the two pairs
-- (81.00 vs 115.95 minutes, and 77.88 vs 94.08) as two genuinely
-- different performances, not duplicates. Nothing was deleted on the
-- strength of it.

SELECT
    event_id,
    athlete_id,
    COUNT(DISTINCT result_id) AS n_results,
    LISTAGG(DISTINCT division, ', ') AS divisions,
    LISTAGG(result_id, ', ') AS result_ids
FROM SPORTS_ANALYTICS_DB.RAW_BRONZE.pacing_obt
GROUP BY event_id, athlete_id
HAVING COUNT(DISTINCT result_id) > 1
ORDER BY n_results DESC;
