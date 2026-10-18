-- TODO: Hand-build the analyst dashboards in the Metabase UI per the question→chart
--   map in the README (Q1 box plot, Q2 scatter, Q3 bar, Q4/Q5 tables, Q6 trend).
--   Manual UI work, no code 

USE ROLE ACCOUNTADMIN;
USE WAREHOUSE COMPUTE_WH;

CREATE OR REPLACE SERVICE SPORTS_ANALYTICS_DB.GOLD_MARKETING.metabase_service
  IN COMPUTE POOL metabase_compute_pool
  FROM SPECIFICATION $$
  spec:
    containers:
      - name: metabase
        image: __REGISTRY_URL__/sports_analytics_db/gold_marketing/metabase_repo/metabase:v12
        env:
          MB_DB_TYPE: h2
    endpoints:
      - name: metabase-ui
        port: 3000
        public: true
  $$;