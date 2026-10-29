{{ config(materialized='table') }}

with base_dates as (
    {{ dbt.date_spine(
        'day',
        "to_date('2020-01-01', 'YYYY-MM-DD')",
        "to_date('2030-01-01', 'YYYY-MM-DD')"
    ) }}
    ),
    final as (
        select
          cast(date_day as date) as date_day
        from base_dates
    )
    select
      *
    from final
    where 1=1
    and date_day >= to_date('2020-01-01', 'YYYY-MM-DD')
    and date_day <= to_date('2030-01-01', 'YYYY-MM-DD')  