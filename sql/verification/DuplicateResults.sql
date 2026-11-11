-- sql/verification/DuplicateResults.sql
--
-- What it is: the headline Q5 uniqueness counts — total rows, distinct
-- result_ids, and the difference between them. Companion to Dupchecks.sql.

SELECT
    COUNT(*) AS n_results,
    COUNT(DISTINCT result_id) AS n_distinct_result_ids,
    COUNT(*) - COUNT(DISTINCT result_id) AS n_duplicate_rows
FROM SPORTS_ANALYTICS_DB.RAW_BRONZE.pacing_obt;
