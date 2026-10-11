-- Step 1: Ingest raw data via Snowpark Python procedure
-- TODO: retire the HYROX_SEASON constant — season is nullable now; HYROX_RAW_SEASON_8 is a legacy name.

USE ROLE ACCOUNTADMIN;
USE DATABASE SPORTS_ANALYTICS_DB;

-- Step 1: Ingest raw data via Snowpark Python procedure
USE SCHEMA SPORTS_ANALYTICS_DB.RAW_BRONZE;
CREATE OR REPLACE TASK task_step1_ingest
  SCHEDULE = '1440 MINUTE' -- Run once per day
AS
  EXECUTE JOB SERVICE
    IN COMPUTE POOL dbt_compute_pool
    NAME = SPORTS_ANALYTICS_DB.RAW_BRONZE.ingest_job
    FROM SPECIFICATION $$
    spec:
      containers:
        - name: ingest-runner
          image: <SNOWFLAKE_ACCOUNT>.registry.snowflakecomputing.com/sports_analytics_db/raw_bronze/dbt_repo/ingest-runner:v12
          env:
            HYROX_SEASON: "8"
            HYROX_MAX_ROWS: "0"
          command: ["python", "scripts/raw_ingest.py"]
    $$;

-- Step 2: Run dbt Silver Models via SPCS Job Task (Serverless)
USE SCHEMA SPORTS_ANALYTICS_DB.RAW_BRONZE;
CREATE OR REPLACE TASK task_step2_dbt_silver
  AFTER task_step1_ingest
AS
  EXECUTE JOB SERVICE
    IN COMPUTE POOL dbt_compute_pool
    NAME = SPORTS_ANALYTICS_DB.SILVER.dbt_silver_job
    FROM SPECIFICATION $$
    spec:
      containers:
        - name: dbt-silver
          image: <SNOWFLAKE_ACCOUNT>.registry.snowflakecomputing.com/sports_analytics_db/raw_bronze/dbt_repo/dbt-runner:v12
          command: ["sh", "-c", "dbt run --select silver --profiles-dir . && dbt test --select silver --profiles-dir ."]
    $$;

-- Step 3: Run WAP Audit Gate via SPCS Job Service
USE SCHEMA SPORTS_ANALYTICS_DB.RAW_BRONZE;
CREATE OR REPLACE TASK task_step3_wap_audit
  AFTER task_step2_dbt_silver
AS
  EXECUTE JOB SERVICE
    IN COMPUTE POOL dbt_compute_pool
    NAME = SPORTS_ANALYTICS_DB.SILVER.wap_job
    FROM SPECIFICATION $$
    spec:
      containers:
        - name: wap-runner
          image: <SNOWFLAKE_ACCOUNT>.registry.snowflakecomputing.com/sports_analytics_db/raw_bronze/dbt_repo/ingest-runner:v12
          command: ["python", "scripts/wap_transforms.py"]
    $$;

-- Step 4: Run dbt Gold Models via SPCS Job Task (Serverless)
USE SCHEMA SPORTS_ANALYTICS_DB.RAW_BRONZE;
CREATE OR REPLACE TASK task_step4_dbt_gold
  AFTER task_step3_wap_audit
AS
  EXECUTE JOB SERVICE
    IN COMPUTE POOL dbt_compute_pool
    NAME = SPORTS_ANALYTICS_DB.GOLD_MARKETING.dbt_gold_job
    FROM SPECIFICATION $$
    spec:
      containers:
        - name: dbt-gold
          image: <SNOWFLAKE_ACCOUNT>.registry.snowflakecomputing.com/sports_analytics_db/raw_bronze/dbt_repo/dbt-runner:v12
          command: ["sh", "-c", "dbt run --select gold --profiles-dir . && dbt test --select gold --profiles-dir ."]
    $$;

-- Step 5: Sync curated Gold records to Neo4j knowledge graph
USE SCHEMA SPORTS_ANALYTICS_DB.RAW_BRONZE;
CREATE OR REPLACE TASK task_step5_neo4j_graph
AFTER task_step4_dbt_gold
AS CALL SPORTS_ANALYTICS_DB.RAW_BRONZE.sp_sync_neo4j_graph();

-- Resume Task Chain (Must be resumed in reverse dependency order)
USE SCHEMA SPORTS_ANALYTICS_DB.RAW_BRONZE;
ALTER TASK task_step5_neo4j_graph RESUME;
ALTER TASK task_step4_dbt_gold RESUME;
ALTER TASK task_step3_wap_audit RESUME;
ALTER TASK task_step2_dbt_silver RESUME;
ALTER TASK task_step1_ingest RESUME;