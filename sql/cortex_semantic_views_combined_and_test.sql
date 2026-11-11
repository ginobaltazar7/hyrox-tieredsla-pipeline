-- Sources: CreateSemanticView_Describe Q1_station_long_and_Q2_station_degradation_Q2_deviation_correlation.sql
-- (HYROX_Q1_Q2_SEMANTIC_VIEW) and CreateSemanticView_Q1_station_variance.sql
-- (Q1_TEST_SEMANTIC_VIEW). 
--
-- Q1_TEST_SEMANTIC_VIEW (minimal Cortex Analyst test view)
CREATE OR REPLACE SEMANTIC VIEW SPORTS_ANALYTICS_DB.RAW_BRONZE.Q1_TEST_SEMANTIC_VIEW
(
    q1 AS SPORTS_ANALYTICS_DB.RAW_BRONZE.Q1_STATION_VARIANCE PRIMARY KEY (STATION)
)
FACTS (
    q1.TRANSITION_TIME_VARIANCE AS q1.TRANSITION_TIME_VARIANCE COMMENT 'Precomputed sample VARIANCE of station transition time, minutes squared. One row per station, n = 400 results per station. Group by station only. Do NOT sum across stations — a summed variance is meaningless.',
    q1.N_OBS AS q1.N_OBS COMMENT 'Number of elite/pro results behind this station variance. 400 for every station.'
)
DIMENSIONS (
    q1.STATION AS q1.STATION COMMENT 'Hyrox station name, for example SLEDPULL, WALLBALLS, SKIERG. Group by this column.'
)
COMMENT = 'Minimal Cortex Analyst test view: Q1 station variance only. Not the full demo view.';

-- HYROX_Q1_Q2_SEMANTIC_VIEW (full demo view over four tables) — PARTIAL, bare form, no AS <sql_expr>; see the README's Cortex section
CREATE OR REPLACE SEMANTIC VIEW SPORTS_ANALYTICS_DB.RAW_BRONZE.HYROX_Q1_Q2_SEMANTIC_VIEW
TABLES (
    q1v AS SPORTS_ANALYTICS_DB.RAW_BRONZE.Q1_STATION_VARIANCE PRIMARY KEY (STATION) COMMENT 'One row per station, elite/pro only. Precomputed station-transition variance.',
    q1l AS SPORTS_ANALYTICS_DB.RAW_BRONZE.Q1_STATION_LONG PRIMARY KEY (RESULT_ID, STATION) COMMENT 'One row per result per station, elite/pro only, 3,200 rows. Per-result transition times, not aggregated.',
    q2d AS SPORTS_ANALYTICS_DB.RAW_BRONZE.Q2_STATION_DEGRADATION PRIMARY KEY (RESULT_ID) COMMENT 'One row per result, all divisions, 5,000 rows. First-km deviation and station degradation per result.',
    q2c AS SPORTS_ANALYTICS_DB.RAW_BRONZE.Q2_DEVIATION_CORRELATION PRIMARY KEY (DIVISION) COMMENT 'One row per division plus a pooled row covering all 5,000 results. Precomputed averages and correlation. Do not average these averages again, and do not sum N across all rows.'
)
FACTS (
    q1v.transition_time_variance COMMENT 'Precomputed sample VARIANCE of station transition time. Group by station only. Do NOT sum across stations.',
    q1v.n_obs COMMENT 'Results behind the station variance. 400 for every station.',
    q1l.transition_time COMMENT 'Transition time in minutes for one result at one station. Average this by station for the Q1 average.',
    q2d.first_km_deviation COMMENT 'Run1 minus the athlete mean of runs 1 to 8, in minutes. Negative means the athlete started faster than their own mean.',
    q2d.station_degradation COMMENT 'Wallballs time minus skierg time, in minutes. Positive means the athlete slowed from first to last station.',
    q2c.n COMMENT 'Results in this division. Pooled row is 5,000.',
    q2c.avg_deviation COMMENT 'Precomputed average first-km deviation for this division. Do not average again.',
    q2c.avg_degradation COMMENT 'Precomputed average station degradation for this division. Do not average again.',
    q2c.corr_dev_vs_degradation COMMENT 'Precomputed correlation between starting deviation and degradation for this division. Association, not causation.'
)
DIMENSIONS (
    q1v.station COMMENT 'Hyrox station, for example SLEDPULL_TIME, WALLBALLS. Group by this column.',
    q1l.station COMMENT 'Hyrox station in the long table. Same station names as q1v.',
    q1l.division COMMENT 'Division of the result in the long table. This table is elite/pro divisions only.',
    q2d.division COMMENT 'Division of the result: doubles, open, pro, pro_doubles, elite, elite_doubles.',
    q2c.division COMMENT 'Division for the correlation row, or the pooled row covering all divisions.'
)
METRICS (
    q1l.avg_transition_time AS AVG(q1l.transition_time) COMMENT 'Average transition time in minutes, grouped by station, over the elite/pro long table.',
    q2d.avg_first_km_deviation AS AVG(q2d.first_km_deviation) COMMENT 'Average first-km deviation in minutes, grouped by division, or pooled over all 5,000 results.',
    q2d.avg_station_degradation AS AVG(q2d.station_degradation) COMMENT 'Average station degradation in minutes, grouped by division, or pooled over all 5,000 results.'
)
COMMENT = 'Full Hyrox Q1/Q2 demo view. Tables have different grains and no relationships: answer each question from a single table. No location, season, points, or podium data is in this view, and no lsa race result is in this view.';
