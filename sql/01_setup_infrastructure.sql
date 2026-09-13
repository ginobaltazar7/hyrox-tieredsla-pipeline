-- Description: Provisions database tiers, external network rules for API access, and the serverless compute pool required to host containerized workloads natively inside Snowflake.
USE ROLE ACCOUNTADMIN;
CREATE DATABASE IF NOT EXISTS SPORTS_ANALYTICS_DB;
CREATE SCHEMA IF NOT EXISTS SPORTS_ANALYTICS_DB.RAW_BRONZE;
CREATE SCHEMA IF NOT EXISTS SPORTS_ANALYTICS_DB.SILVER;
CREATE SCHEMA IF NOT EXISTS SPORTS_ANALYTICS_DB.GOLD_MARKETING;
CREATE SCHEMA IF NOT EXISTS SPORTS_ANALYTICS_DB.GOLD_FINANCE;

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

-- Check if compute pool is active and ready
SHOW COMPUTE POOLS LIKE 'dbt_compute_pool';
SHOW COMPUTE POOLS LIKE 'metabase_compute_pool';


-- Verify image repository contains the latest runner images
SHOW IMAGES IN IMAGE REPOSITORY SPORTS_ANALYTICS_DB.RAW_BRONZE.dbt_repo;

-- Verify target databases and schemas exist
SHOW SCHEMAS IN DATABASE SPORTS_ANALYTICS_DB;

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

-- Create Hyrox Table in RAW_BRONZE for Ingested Data
CREATE OR REPLACE TABLE SPORTS_ANALYTICS_DB.RAW_BRONZE.HYROX_RAW_SEASON_8 (
    athlete_id VARCHAR,
    name VARCHAR,
    season VARCHAR,
    location VARCHAR,
    total_time_minutes FLOAT,
    division VARCHAR,
    updated_at TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP()
);

DESCRIBE TABLE SPORTS_ANALYTICS_DB.RAW_BRONZE.HYROX_RAW_SEASON_8;

-- Egress network rule and external access integration for pyrox-client package retrieval
-- Works only with Snowflake accounts that have External Network Access enabled and configured and not a trial account. If you are using a trial account, you can skip this step and manually install the pyrox-client package in your local environment.
-- CREATE OR REPLACE NETWORK RULE pyrox_api_net_rule
--  MODE = EGRESS
--  TYPE = HOST_PORT
--  VALUE_LIST = ('pypi.org', 'github.com', 'api.github.com');

-- CREATE OR REPLACE EXTERNAL ACCESS INTEGRATION pyrox_external_access_integration
--  ALLOWED_NETWORK_RULES = (pyrox_api_net_rule)
--  ENABLED = TRUE;

