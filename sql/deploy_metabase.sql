USE ROLE ACCOUNTADMIN;
USE WAREHOUSE COMPUTE_WH;

CREATE OR REPLACE SERVICE SPORTS_ANALYTICS_DB.GOLD_MARKETING.metabase_service
  IN COMPUTE POOL metabase_compute_pool
  FROM SPECIFICATION $$
  spec:
    containers:
      - name: metabase
        image: mrimflq-gt47043.registry.snowflakecomputing.com/sports_analytics_db/raw_bronze/dbt_repo/metabase:v3
        env:
          MB_DB_TYPE: h2
    endpoints:
      - name: metabase-ui
        port: 3000
        public: true
  $$;