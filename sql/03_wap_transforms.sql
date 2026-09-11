-- Description: Executes the WAP lifecycle, leveraging an Isolation Forest machine learning model to audit race timing distributions before publishing to tiered Gold schemas.
CREATE OR REPLACE PROCEDURE SPORTS_ANALYTICS_DB.SILVER.sp_snowpatrol_wap_gate()
RETURNS STRING
LANGUAGE PYTHON
RUNTIME_VERSION = '3.10'
PACKAGES = ('snowflake-snowpark-python', 'pandas', 'scikit-learn')
HANDLER = 'snowpatrol_wap_handler'
AS
$$
import pandas as pd
from sklearn.ensemble import IsolationForest
from snowflake.snowpark import Session

def snowpatrol_wap_handler(session: Session) -> str:
    # Write Stage: Materialize Silver staging table from Bronze
    session.sql("""
        CREATE OR REPLACE TABLE SPORTS_ANALYTICS_DB.SILVER.stg_race_performance_wap AS
        SELECT athlete_id, name, season, location, total_time_minutes, division
        FROM SPORTS_ANALYTICS_DB.RAW_BRONZE.hyrox_raw_season_8
    """).collect()
    
    # Audit Stage: Run Isolation Forest anomaly detection gate
    df = session.sql("SELECT athlete_id, total_time_minutes FROM SPORTS_ANALYTICS_DB.SILVER.stg_race_performance_wap").to_pandas()
    if len(df) > 10:
        model = IsolationForest(contamination=0.01, random_state=42)
        df['anomaly_score'] = model.fit_predict(df[['total_time_minutes']])
        anomalies_detected = (df['anomaly_score'] == -1).sum()
        
        if anomalies_detected > 5:
            raise ValueError(f"SNOWPATROL WAP GATE HALTED: Detected {anomalies_detected} pacing anomalies exceeding threshold. Promotion aborted.")

    # Publish Stage: Promote verified records to Marketing and Finance Gold tiers
    session.sql("CREATE OR REPLACE TABLE SPORTS_ANALYTICS_DB.GOLD_MARKETING.pacing_obt AS SELECT * FROM SPORTS_ANALYTICS_DB.SILVER.stg_race_performance_wap").collect()
    
session.sql("CREATE OR REPLACE TABLE SPORTS_ANALYTICS_DB.GOLD_FINANCE.fact_race_performance_audit AS SELECT * FROM SPORTS_ANALYTICS_DB.SILVER.stg_race_performance_wap").collect()
    return "Snowpatrol WAP Audit Passed: Verified and published cleanly to Gold."
$$;
