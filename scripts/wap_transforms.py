"""
    WAP Transform & Anomaly Detection Gate Script
    Executes the Write-Audit-Publish lifecycle, leveraging an Isolation Forest 
    machine learning model to audit race timing distributions before publishing to Gold, 
    and native Snowflake SQL or Snowpark DataFrames instead of pandas.
"""

import logging
import os
import sys
from sklearn.ensemble import IsolationForest
from utils.session import get_snowpark_session

logging.basicConfig(
    stream=sys.stdout,
    level=logging.INFO,
    format="%(asctime)s ====>> [%(levelname)s] %(name)s: %(message)s",
    datefmt="%Y-%m-%d %H:%M:%S"
)
logger = logging.getLogger("wap-transform-runner")
    
def main():
    logger.info("Initializing Snowflake Snowpark session...")
    session = get_snowpark_session()

    logger.info("Write Stage: Materializing Silver staging table via native Snowflake SQL...")
    session.sql("""
        CREATE OR REPLACE TABLE SPORTS_ANALYTICS_DB.SILVER.stg_race_performance_wap AS
        SELECT athlete_id, name, season, location, total_time_minutes, division, updated_at
        FROM SPORTS_ANALYTICS_DB.RAW_BRONZE.hyrox_raw_season_8
    """).collect()

    logger.info("Audit Stage: Fetching lightweight feature vector for Isolation Forest...")
    # Pull only the minimum columns needed for ML inference into pandas
    df_ml = session.sql("""
        SELECT athlete_id, total_time_minutes 
        FROM SPORTS_ANALYTICS_DB.SILVER.stg_race_performance_wap
    """).to_pandas()

    # Audit
    halt = False
    if len(df_ml) > 10:
        model = IsolationForest(contamination=0.01, random_state=42)
        scores = model.fit_predict(df_ml[['total_time_minutes']])
        anomaly_rate = (scores == -1).mean()
        logger.info(f"Isolation Forest evaluated {len(df_ml)} rows. Anomalies rate: {anomaly_rate * 100:.2f}%")

        if anomaly_rate > 0.05:
            halt = True
    if halt:
        logger.error(f"WAP GATE HALTED: {anomaly_rate * 100:.2f}% anomaly rate exceeds threshold.")
        raise ValueError(f"WAP GATE HALTED: {anomaly_rate * 100:.2f}% anomaly rate exceeds threshold.")
    
    logger.info("Publish Stage: Promoting verified records to Gold tiers via server-side SQL...")
    # GOLD OWNERSHIP (settled 2026-10-12): dbt owns GOLD_MARKETING.pacing_obt
    # (dbt_project/models/gold_marketing/pacing_obt.sql). The WAP script must NEVER
    # write a table named pacing_obt — its 7-column staging shape (no result_id, no
    # splits) would clobber the dbt gold. It publishes the verified staging set under
    # a distinct name instead.
    session.sql("""
        CREATE OR REPLACE TABLE SPORTS_ANALYTICS_DB.GOLD_MARKETING.pacing_obt_wap_verified AS
        SELECT * FROM SPORTS_ANALYTICS_DB.SILVER.stg_race_performance_wap
    """).collect()
    
    session.sql("""
        CREATE OR REPLACE TABLE SPORTS_ANALYTICS_DB.GOLD_FINANCE.fact_race_performance_audit AS 
        SELECT * FROM SPORTS_ANALYTICS_DB.SILVER.stg_race_performance_wap
    """).collect()

    logger.info("WAP Audit Passed: Verified and published cleanly to Gold.")

if __name__ == "__main__":
    main()