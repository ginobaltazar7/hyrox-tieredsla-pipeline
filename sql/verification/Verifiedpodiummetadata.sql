-- sql/verification/Verifiedpodiummetadata.sql
--
-- What it is: the evidence behind Q4 being blocked — a search of the
-- pacing_obt columns for anything like penalty, points, rank,
-- verification, podium, place or judge. The sample has no such columns,
-- so ranking points after penalties cannot be computed here, and
-- inventing points would be worse than leaving the question open.
-- Keep this file as the record of that check.

SELECT column_name, data_type
FROM SPORTS_ANALYTICS_DB.INFORMATION_SCHEMA.COLUMNS
WHERE table_schema = 'RAW_BRONZE'
  AND table_name = 'PACING_OBT'
  AND (LOWER(column_name) LIKE '%penalt%'
    OR LOWER(column_name) LIKE '%point%'
    OR LOWER(column_name) LIKE '%rank%'
    OR LOWER(column_name) LIKE '%verif%'
    OR LOWER(column_name) LIKE '%podium%'
    OR LOWER(column_name) LIKE '%place%'
    OR LOWER(column_name) LIKE '%judge%')
ORDER BY column_name;
