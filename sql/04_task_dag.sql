SQL
-- Step 1: Ingest raw data via Snowpark Python procedure
CREATE OR REPLACE TASK SPORTS_ANALYTICS_DB.RAW_BRONZE.task_step1_ingest
  WAREHOUSE = 'WH_MARKETING_XS'
  SCHEDULE = '60 MINUTE'
AS
  CALL SPORTS_ANALYTICS_DB.RAW_BRONZE.sp_ingest_hyrox(8);

-- Step 2: Run dbt Silver Models (builds stg_hyrox_races via dbt)
CREATE OR REPLACE TASK SPORTS_ANALYTICS_DB.SILVER.task_step2_dbt_silver
  WAREHOUSE = 'WH_MARKETING_XS'
  AFTER SPORTS_ANALYTICS_DB.RAW_BRONZE.task_step1_ingest
AS
  EXECUTE SERVICE SPORTS_ANALYTICS_DB.SILVER.dbt_silver_job;

-- Step 3: Run Snowpatrol WAP Audit Gate on dbt's Silver output
CREATE OR REPLACE TASK SPORTS_ANALYTICS_DB.SILVER.task_step3_wap_audit
  WAREHOUSE = 'WH_MARKETING_XS'
  AFTER SPORTS_ANALYTICS_DB.SILVER.task_step2_dbt_silver
AS
  CALL SPORTS_ANALYTICS_DB.SILVER.sp_snowpatrol_wap_gate();

-- Step 4: Run dbt Gold Models (builds pacing_obt and snapshots if audit passes)
CREATE OR REPLACE TASK SPORTS_ANALYTICS_DB.GOLD_MARKETING.task_step4_dbt_gold
  WAREHOUSE = 'WH_MARKETING_XS'
  AFTER SPORTS_ANALYTICS_DB.SILVER.task_step3_wap_audit
AS
  EXECUTE SERVICE SPORTS_ANALYTICS_DB.GOLD_MARKETING.dbt_gold_job;

-- Resume Task Chain
ALTER TASK SPORTS_ANALYTICS_DB.GOLD_MARKETING.task_step4_dbt_gold RESUME;
ALTER TASK SPORTS_ANALYTICS_DB.SILVER.task_step3_wap_audit RESUME;
ALTER TASK SPORTS_ANALYTICS_DB.SILVER.task_step2_dbt_silver RESUME;
ALTER TASK SPORTS_ANALYTICS_DB.RAW_BRONZE.task_step1_ingest RESUME;
