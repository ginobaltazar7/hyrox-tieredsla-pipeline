{{ config(materialized='table') }}
select
    station,
    to_date('2020-01-01', 'YYYY-MM-DD') as variance_date,
    variance(transition_time) as transition_time_variance,
    count(*) as n_obs
from {{ ref('q1_station_long') }}
group by station, to_date('2020-01-01', 'YYYY-MM-DD')