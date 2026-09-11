-- Description: Provisions database tiers, external network rules for API access, and the serverless compute pool required to host containerized workloads natively inside Snowflake.
SQL
CREATE DATABASE IF NOT EXISTS SPORTS_ANALYTICS_DB;
CREATE SCHEMA IF NOT EXISTS SPORTS_ANALYTICS_DB.RAW_BRONZE;
CREATE SCHEMA IF NOT EXISTS SPORTS_ANALYTICS_DB.SILVER;
CREATE SCHEMA IF NOT EXISTS SPORTS_ANALYTICS_DB.GOLD_MARKETING;
CREATE SCHEMA IF NOT EXISTS SPORTS_ANALYTICS_DB.GOLD_FINANCE;

-- Compute pool for running Metabase natively via Snowpark Container Services
CREATE COMPUTE POOL IF NOT EXISTS metabase_compute_pool
  MIN_NODES = 1
  MAX_NODES = 1
  INSTANCE_FAMILY = CPU_X64_XS
  AUTO_RESUME = TRUE;

-- Compute pool for containerized dbt workloads 
CREATE COMPUTE POOL IF NOT EXISTS dbt_compute_pool 
  MIN_NODES = 1 
  MAX_NODES = 1 
  INSTANCE_FAMILY = CPU_X64_XS 
  AUTO_RESUME = TRUE;

-- Image Repository for storing containerized dbt Core images inside Snowflake CREATE IMAGE REPOSITORY IF NOT EXISTS SPORTS_ANALYTICS_DB.RAW_BRONZE.dbt_repo;

-- Egress network rule and external access integration for pyrox-client package retrieval
CREATE OR REPLACE NETWORK RULE pyrox_api_net_rule
  MODE = EGRESS
  TYPE = HOST_PORT
  VALUE_LIST = ('pypi.org', 'github.com', 'api.github.com');

CREATE OR REPLACE EXTERNAL ACCESS INTEGRATION pyrox_external_access_integration
  ALLOWED_NETWORK_RULES = (pyrox_api_net_rule)
  ENABLED = TRUE;

