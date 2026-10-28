{{ config(materialized='table') }}
select
  result_id,
  division,
  split_name as station,
  split_time as transition_time
from {{ ref('pacing_obt') }}
unpivot (split_time for split_name in (
  skierg_time, sledpush_time, sledpull_time,
  burpeebroadjump_time, rowerg_time, farmerscarry_time,
  sandbaglunges_time, wallballs_time
))
where division in ('pro', 'pro_doubles', 'elite', 'elite_doubles')