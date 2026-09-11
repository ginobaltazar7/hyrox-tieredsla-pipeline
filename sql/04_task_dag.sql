-- Step 1: Ingest raw data via Snowpark Python procedure
CREATE OR REPLACE TASK SPORTS_ANALYTICS_DB.RAW_BRONZE.task_step1_ingest
  SCHEDULE = '60 MINUTE'
AS
  EXECUTE JOB SERVICE
    IN COMPUTE POOL dbt_compute_pool
    NAME = SPORTS_ANALYTICS_DB.RAW_BRONZE.ingest_job
    FROM SPECIFICATION $$
    spec:
      containers:
        - name: ingest-runner
          image: /sports_analytics_db/raw_bronze/dbt_repo/ingest-runner:latest
          env:
            HYROX_SEASON: "8"
            MAX_ROWS: "5000"
          command: ["python", "scripts/raw_ingest.py"]
    $$;

-- Step 2: Run dbt Silver Models via SPCS Job Task (Serverless)
CREATE OR REPLACE TASK SPORTS_ANALYTICS_DB.SILVER.task_step2_dbt_silver
  AFTER SPORTS_ANALYTICS_DB.RAW_BRONZE.task_step1_ingest
AS
  EXECUTE JOB SERVICE
    IN COMPUTE POOL dbt_compute_pool
    NAME = SPORTS_ANALYTICS_DB.SILVER.dbt_silver_job
    FROM SPECIFICATION $$
    spec:
      containers:
        - name: dbt-silver
          image: /sports_analytics_db/raw_bronze/dbt_repo/dbt-runner:latest
          command: ["sh", "-c", "dbt run --select silver --profiles-dir . && dbt test --select silver --profiles-dir ."]
    $$;

-- Step 3: Run Snowpatrol WAP Audit Gate on dbt's Silver output
CREATE OR REPLACE TASK SPORTS_ANALYTICS_DB.SILVER.task_step3_wap_audit
  WAREHOUSE = 'WH_MARKETING_XS'
  AFTER SPORTS_ANALYTICS_DB.SILVER.task_step2_dbt_silver
AS
  CALL SPORTS_ANALYTICS_DB.SILVER.sp_snowpatrol_wap_gate();

-- Step 4: Run dbt Gold Models via SPCS Job Task (Serverless)
CREATE OR REPLACE TASK SPORTS_ANALYTICS_DB.GOLD_MARKETING.task_step4_dbt_gold
  AFTER SPORTS_ANALYTICS_DB.SILVER.task_step3_wap_audit
AS
  EXECUTE JOB SERVICE
    IN COMPUTE POOL dbt_compute_pool
    NAME = SPORTS_ANALYTICS_DB.GOLD_MARKETING.dbt_gold_job
    FROM SPECIFICATION $$
    spec:
      containers:
        - name: dbt-gold
          image: /sports_analytics_db/raw_bronze/dbt_repo/dbt-runner:latest
          command: ["sh", "-c", "dbt run --select gold --profiles-dir . && dbt test --select gold --profiles-dir ."]
    $$;

-- Resume Task Chain
ALTER TASK SPORTS_ANALYTICS_DB.GOLD_MARKETING.task_step4_dbt_gold RESUME;
ALTER TASK SPORTS_ANALYTICS_DB.SILVER.task_step3_wap_audit RESUME;
ALTER TASK SPORTS_ANALYTICS_DB.SILVER.task_step2_dbt_silver RESUME;
ALTER TASK SPORTS_ANALYTICS_DB.RAW_BRONZE.task_step1_ingest RESUME;
