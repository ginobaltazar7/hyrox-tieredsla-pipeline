-- Description: Chains the ingestion and WAP transformation stored procedures into an automated, serverless Snowflake Task DAG
SQL
CREATE OR REPLACE TASK SPORTS_ANALYTICS_DB.RAW_BRONZE.task_step1_ingest
  WAREHOUSE = 'WH_MARKETING_XS'
  SCHEDULE = '60 MINUTE'
AS
  CALL SPORTS_ANALYTICS_DB.RAW_BRONZE.sp_ingest_hyrox(8);

CREATE OR REPLACE TASK SPORTS_ANALYTICS_DB.SILVER.task_step2_snowpatrol_wap
  WAREHOUSE = 'WH_MARKETING_XS'
  AFTER SPORTS_ANALYTICS_DB.RAW_BRONZE.task_step1_ingest
AS
  CALL SPORTS_ANALYTICS_DB.SILVER.sp_snowpatrol_wap_gate();

-- Resume tasks to activate execution
ALTER TASK SPORTS_ANALYTICS_DB.SILVER.task_step2_snowpatrol_wap RESUME;
ALTER TASK SPORTS_ANALYTICS_DB.RAW_BRONZE.task_step1_ingest RESUME;
