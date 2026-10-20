-- Description: Provisions database tiers, external network rules for API access, and the serverless compute pool required to host containerized workloads natively inside Snowflake.
USE ROLE ACCOUNTADMIN;
CREATE DATABASE IF NOT EXISTS SPORTS_ANALYTICS_DB;
CREATE SCHEMA IF NOT EXISTS SPORTS_ANALYTICS_DB.RAW_BRONZE;
CREATE SCHEMA IF NOT EXISTS SPORTS_ANALYTICS_DB.SILVER;
CREATE SCHEMA IF NOT EXISTS SPORTS_ANALYTICS_DB.GOLD_MARKETING;
CREATE SCHEMA IF NOT EXISTS SPORTS_ANALYTICS_DB.GOLD_FINANCE;

-- Named Internal Stage for Ingested Data
 CREATE STAGE IF NOT EXISTS SPORTS_ANALYTICS_DB.RAW_BRONZE.ingest_stage
  ENCRYPTION = (TYPE = 'SNOWFLAKE_SSE');

-- Image Repository for project containers
CREATE IMAGE REPOSITORY IF NOT EXISTS SPORTS_ANALYTICS_DB.RAW_BRONZE.dbt_repo;
CREATE IMAGE REPOSITORY IF NOT EXISTS SPORTS_ANALYTICS_DB.GOLD_MARKETING.metabase_repo;

-- Compute Pool for Metabase BI
CREATE COMPUTE POOL IF NOT EXISTS metabase_compute_pool
  MIN_NODES = 1
  MAX_NODES = 1
  INSTANCE_FAMILY = CPU_X64_XS
  AUTO_RESUME = TRUE;

-- Compute Pool for containerized dbt workloads
CREATE COMPUTE POOL IF NOT EXISTS dbt_compute_pool
  MIN_NODES = 1
  MAX_NODES = 1
  INSTANCE_FAMILY = CPU_X64_XS
  AUTO_RESUME = TRUE;

-- Resume Compute Pools
ALTER COMPUTE POOL dbt_compute_pool RESUME;
ALTER COMPUTE POOL metabase_compute_pool RESUME;

-- Check if compute pool is active and ready, unless AUTO_RESUME is enabled (which it is in this case), uncomment otherwise
-- SHOW COMPUTE POOLS LIKE 'dbt_compute_pool';
-- SHOW COMPUTE POOLS LIKE 'metabase_compute_pool';

-- Verify image repository contains the latest runner images
SHOW IMAGES IN IMAGE REPOSITORY SPORTS_ANALYTICS_DB.RAW_BRONZE.dbt_repo;

-- Verify target databases and schemas exist
SHOW SCHEMAS IN DATABASE SPORTS_ANALYTICS_DB;

-- Create Hyrox Table in RAW_BRONZE for Ingested Data
CREATE OR REPLACE TABLE SPORTS_ANALYTICS_DB.RAW_BRONZE.HYROX_RAW_SEASON_8 (
    result_id VARCHAR NOT NULL,   -- coalesce(source_result_id, synthetic), the raw grain
    source_result_id VARCHAR,     -- raw value, nullable (698K nulls observed)
    event_id VARCHAR NOT NULL,    -- zero nulls, anchors the synthetic hash
    athlete_id VARCHAR NOT NULL,  -- derived sha256(name|gender|nationality|age_group), rule v1
    name VARCHAR, gender VARCHAR, nationality VARCHAR, age_group VARCHAR,
    division VARCHAR,             -- doubles/relay encoded here (elite_doubles, doubles, pro_doubles, relay)
    season INT,                   -- NULLABLE: do not default missing to 8
    year INT, event_name VARCHAR, location VARCHAR,
    total_time_minutes FLOAT,
    run1_time FLOAT, run2_time FLOAT, run3_time FLOAT, run4_time FLOAT,
    run5_time FLOAT, run6_time FLOAT, run7_time FLOAT, run8_time FLOAT,
    skierg_time FLOAT, sledpush_time FLOAT, sledpull_time FLOAT,
    burpeebroadjump_time FLOAT, rowerg_time FLOAT, farmerscarry_time FLOAT,
    sandbaglunges_time FLOAT, wallballs_time FLOAT,
    roxzone_time FLOAT, run_time FLOAT, work_time FLOAT, best_run_lap FLOAT,
    updated_at TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP()  -- pipeline load time
);

DESCRIBE TABLE SPORTS_ANALYTICS_DB.RAW_BRONZE.HYROX_RAW_SEASON_8;

-- Establish Secure GitHub API Integration
CREATE OR REPLACE API INTEGRATION github_api_integration
  API_PROVIDER = git_https_api
  API_ALLOWED_PREFIXES = ('https://github.com/ginobaltazar7/hyrox-tieredsla-pipeline')
  ENABLED = TRUE;

-- Register Native Git Repository Stage
CREATE OR REPLACE GIT REPOSITORY SPORTS_ANALYTICS_DB.RAW_BRONZE.hyrox_repo
  API_INTEGRATION = github_api_integration
  ORIGIN = 'https://github.com/ginobaltazar7/hyrox-tieredsla-pipeline';

-- Fetch Code and Verify Staging Files
ALTER GIT REPOSITORY SPORTS_ANALYTICS_DB.RAW_BRONZE.hyrox_repo FETCH;
LS @SPORTS_ANALYTICS_DB.RAW_BRONZE.hyrox_repo/branches/main;  
SHOW GIT BRANCHES IN SPORTS_ANALYTICS_DB.RAW_BRONZE.hyrox_repo;


-- Egress network rule and external access integration for pyrox-client package retrieval
-- Works only with Snowflake accounts that have External Network Access enabled and configured and not a trial account. If you are using a trial account, you can skip this step and manually install the pyrox-client package in your local environment.
-- CREATE OR REPLACE NETWORK RULE pyrox_api_net_rule
--  MODE = EGRESS
--  TYPE = HOST_PORT
--  VALUE_LIST = ('pypi.org', 'github.com', 'api.github.com');

-- CREATE OR REPLACE EXTERNAL ACCESS INTEGRATION pyrox_external_access_integration
--  ALLOWED_NETWORK_RULES = (pyrox_api_net_rule)
--  ENABLED = TRUE;

