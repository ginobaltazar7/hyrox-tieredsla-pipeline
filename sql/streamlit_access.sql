-- RUN ORDER: (1) generate the key pair, (2) replace
-- <RSA_PUBLIC_KEY_MIDDLE_LINE> below with the middle line of the public
-- key, (3) run this file. The role must be created before the user, or
-- the CREATE USER fails — a DEFAULT_ROLE has to exist first.
-- RE-RUNS: CREATE USER IF NOT EXISTS silently does nothing if the user
-- already exists, so re-running this file will NOT update the key.
-- To rotate the key, use: ALTER USER HYROX_STREAMLIT_APP
-- SET RSA_PUBLIC_KEY = '<the long middle line of the public key>';
CREATE ROLE IF NOT EXISTS HYROX_APP_READER;

-- Service user for the Streamlit app on Render
-- Fill in <RSA_PUBLIC_KEY_MIDDLE_LINE> from the worksheet or from
-- the openssl command above before running.
CREATE USER IF NOT EXISTS HYROX_STREAMLIT_APP
  TYPE = SERVICE
  DEFAULT_ROLE = HYROX_APP_READER
  DEFAULT_WAREHOUSE = COMPUTE_WH
  RSA_PUBLIC_KEY = '<RSA_PUBLIC_KEY_MIDDLE_LINE>'
  COMMENT = 'Read only user for the HYROX Streamlit app on Render';

-- Grants for the Streamlit app user to read the semantic views and underlying tables
GRANT USAGE ON WAREHOUSE COMPUTE_WH TO ROLE HYROX_APP_READER;
GRANT USAGE ON DATABASE SPORTS_ANALYTICS_DB TO ROLE HYROX_APP_READER;
GRANT USAGE ON SCHEMA SPORTS_ANALYTICS_DB.RAW_BRONZE TO ROLE HYROX_APP_READER;
GRANT SELECT ON TABLE SPORTS_ANALYTICS_DB.RAW_BRONZE.Q1_STATION_VARIANCE TO ROLE HYROX_APP_READER;
GRANT SELECT ON TABLE SPORTS_ANALYTICS_DB.RAW_BRONZE.Q2_STATION_DEGRADATION TO ROLE HYROX_APP_READER;
GRANT SELECT ON TABLE SPORTS_ANALYTICS_DB.RAW_BRONZE.Q2_DEVIATION_CORRELATION TO ROLE HYROX_APP_READER;
GRANT ROLE HYROX_APP_READER TO USER HYROX_STREAMLIT_APP;
