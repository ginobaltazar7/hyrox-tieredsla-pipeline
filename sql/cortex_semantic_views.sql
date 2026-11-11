-- Views captured in full from GET_DDL: the four split views below.
-- HYROX_Q1_Q2_SEMANTIC_VIEW and Q1_TEST_SEMANTIC_VIEW are in
-- cortex_semantic_views_combined_and_test.sql 

-- Run context: the view names below are unqualified, so run this file
-- in SPORTS_ANALYTICS_DB.RAW_BRONZE (or qualify the names yourself).
USE DATABASE SPORTS_ANALYTICS_DB;
USE SCHEMA RAW_BRONZE;

create or replace semantic view HYROX_Q1_VARIANCE_VIEW
tables (
    Q1V as SPORTS_ANALYTICS_DB.RAW_BRONZE.Q1_STATION_VARIANCE primary key (STATION)
)
facts (
    Q1V.TRANSITION_TIME_VARIANCE as q1v.TRANSITION_TIME_VARIANCE comment='Precomputed sample VARIANCE of station transition time. Group by station only. Do NOT sum across stations.',
    Q1V.N_OBS as q1v.N_OBS comment='Results behind the station variance. 400 for every station.'
)
dimensions (
    Q1V.STATION as q1v.STATION comment='Hyrox station, for example SLEDPULL_TIME, WALLBALLS. Group by this column.'
)
comment='Q1 variance only, one row per station, elite/pro, 3,200 splits behind it.';

create or replace semantic view HYROX_Q1_AVERAGE_VIEW
tables (
    Q1L as SPORTS_ANALYTICS_DB.RAW_BRONZE.Q1_STATION_LONG primary key (RESULT_ID,STATION)
)
facts (
    Q1L.TRANSITION_TIME as q1l.TRANSITION_TIME
)
dimensions (
    Q1L.STATION as q1l.STATION,
    Q1L.DIVISION as q1l.DIVISION
)
metrics (
    Q1L.AVG_TRANSITION_TIME as AVG(q1l.transition_time)
)
comment='Q1 average only, one row per result per station, elite/pro, 3,200 rows.';

create or replace semantic view HYROX_Q2_VIEW
tables (
    Q2D as SPORTS_ANALYTICS_DB.RAW_BRONZE.Q2_STATION_DEGRADATION primary key (RESULT_ID)
)
facts (
    Q2D.FIRST_KM_DEVIATION as q2d.FIRST_KM_DEVIATION,
    Q2D.STATION_DEGRADATION as q2d.STATION_DEGRADATION
)
dimensions (
    Q2D.DIVISION as q2d.DIVISION
)
metrics (
    Q2D.AVG_FIRST_KM_DEVIATION as AVG(q2d.first_km_deviation),
    Q2D.AVG_STATION_DEGRADATION as AVG(q2d.station_degradation)
)
comment='Q2 per-result only, 5,000 rows, all divisions.';

create or replace semantic view HYROX_Q2_CORRELATION_VIEW
tables (
    Q2C as SPORTS_ANALYTICS_DB.RAW_BRONZE.Q2_DEVIATION_CORRELATION primary key (DIVISION)
)
facts (
    Q2C.N as q2c.N,
    Q2C.AVG_DEVIATION as q2c.AVG_DEVIATION,
    Q2C.AVG_DEGRADATION as q2c.AVG_DEGRADATION,
    Q2C.CORR_DEV_VS_DEGRADATION as q2c.CORR_DEV_VS_DEGRADATION
)
dimensions (
    Q2C.DIVISION as q2c.DIVISION
)
comment='Q2 correlation only, one row per division plus a pooled row. Do not average the averages again, do not sum N.';
