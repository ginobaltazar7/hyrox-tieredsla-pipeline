"""
    Ingest Runner Script for Hyrox Tiered SLA Pipeline
    This script fetches raw Hyrox race data, validates and transforms it, and loads it into a Snowflake Snowpark session in batches.
    It uses structured logging for telemetry and error tracking.
"""

import logging
import os
import sys
from typing import Generator
import pandas as pd
import pyarrow as pa
import pyarrow.parquet as pq
from pydantic import BaseModel, Field, ValidationError
import pyrox
from snowflake.snowpark import Session

# Configure structured logging to stdout for automatic SPCS log capture and telemetry
logging.basicConfig(
    stream=sys.stdout,
    level=logging.INFO,
    format="%(asctime)s [%(levelname)s] %(name)s: %(message)s",
    datefmt="%Y-%m-%d %H:%M:%S"
)
logger = logging.getLogger("ingest-runner")

class HyroxRecordModel(BaseModel):
    athlete_id: str = Field(..., description="Unique athlete identifier")
    name: str
    season: int
    location: str
    total_time_minutes: float = Field(..., ge=0.0)
    division: str

def get_snowpark_session() -> Session:
    if os.path.exists("/snowflake/session/token"):
        with open("/snowflake/session/token", "r") as f:
            token = f.read().strip()
        return Session.builder.configs({
            "host": os.getenv("SNOWFLAKE_HOST"),
            "account": os.getenv("SNOWFLAKE_ACCOUNT"),
            "token": token,
            "authenticator": "oauth",
            "warehouse": "COMPUTE_WH",
            "database": "SPORTS_ANALYTICS_DB",
            "schema": "RAW_BRONZE"
        }).create()
    else:
        return Session.builder.configs({
            "account": os.getenv("SNOWFLAKE_ACCOUNT"),
            "user": os.getenv("SNOWFLAKE_USER"),
            "password": os.getenv("SNOWFLAKE_PASSWORD"),
            "warehouse": "COMPUTE_WH",
            "database": "SPORTS_ANALYTICS_DB",
            "schema": "RAW_BRONZE"
        }).create()
    
def batch_generator(df: pd.DataFrame, batch_size: int = 1000, max_rows: int = 5000) -> Generator[pd.DataFrame, None, None]:
    total_input_rows = len(df)
    if total_input_rows > max_rows:
        logger.warning(f"Dataset size ({total_input_rows}) exceeds max_rows limit ({max_rows}). Truncating dataset.")
        df = df.head(max_rows)
        total_input_rows = max_rows
        
    records = df.to_dict(orient="records")
    logger.info(f"Starting batch validation and transformation for {total_input_rows} rows in batches of {batch_size}.")
    
    batch_count = 0
    total_valid = 0
    total_invalid = 0

    for i in range(0, len(records), batch_size):
        batch_records = records[i:i+batch_size]
        valid_rows = []
        invalid_in_batch = 0
        
        for row in batch_records:
            try:
                record = HyroxRecordModel(
                    athlete_id=str(row.get("athlete_id", "UNKNOWN")),
                    name=str(row.get("name", "ANONYMOUS")),
                    season=int(row.get("season", 8)),
                    location=str(row.get("location", "UNKNOWN")),
                    total_time_minutes=float(row.get("total_time", 0.0)),
                    division=str(row.get("division", "OPEN"))
                )
                valid_rows.append(record.model_dump())
            except ValidationError as e:
                invalid_in_batch += 1
                logger.debug(f"Validation failed for record {row.get('athlete_id', 'UNKNOWN')}: {e}")
                continue
        
        total_valid += len(valid_rows)
        total_invalid += invalid_in_batch
        batch_count += 1
        
        if valid_rows:
            logger.info(f"Batch {batch_count}: Processed {len(valid_rows)} valid rows ({invalid_in_batch} dropped due to validation).")
            yield pd.DataFrame(valid_rows)

    logger.info(f"Batch generation complete. Total valid rows: {total_valid}, Total dropped rows: {total_invalid}")

def main():
    logger.info("Initializing Snowflake Snowpark session for ingestion runner...")
    session = get_snowpark_session()

    season_num = int(os.getenv("HYROX_SEASON", "8"))
    max_rows = int(os.getenv("MAX_ROWS", "5000"))
    table_name = f"hyrox_raw_season_{season_num}"

    logger.info(f"Fetching raw data for Hyrox Season {season_num} via pyrox client...")
    client = pyrox.PyroxClient()
    df_raw = client.get_season(season=season_num)
    df_raw.columns = [c.lower().replace(" ", "_") for c in df_raw.columns]
    logger.info(f"Successfully fetched raw dataset containing {len(df_raw)} records.")

    logger.info(f"Ensuring target bronze table {table_name} exists and truncating prior snapshot...")
    session.sql(f"""
        CREATE TABLE IF NOT EXISTS {table_name} (
            athlete_id VARCHAR,
            name VARCHAR,
            season INT,
            location VARCHAR,
            total_time_minutes FLOAT,
            division VARCHAR
        )
    """).collect()
    session.sql(f"TRUNCATE TABLE {table_name}").collect()

    loaded_batches = 0
    for batch_idx, batch_df in enumerate(batch_generator(df_raw, batch_size=1000, max_rows=max_rows)):
        file_name = f"batch_{batch_idx}.parquet"
        logger.info(f"Writing batch {batch_idx} to local Parquet file: {file_name}")
        
        table = pa.Table.from_pandas(batch_df)
        pq.write_table(table, file_name, compression='SNAPPY')
        
        logger.info(f"Staging {file_name} to internal Snowflake stage (@~)...")
        session.file.put(file_name, "@~", auto_compress=False, overwrite=True)
        
        logger.info(f"Executing bulk COPY INTO {table_name} from {file_name}...")
        session.sql(f"""
            COPY INTO {table_name}
            FROM @~/{file_name}
            FILE_FORMAT = (TYPE = PARQUET)
            MATCH_BY_COLUMN_NAME = CASE_INSENSITIVE
        """).collect()
        
        if os.path.exists(file_name):
            os.remove(file_name)
        loaded_batches += 1

    logger.info(f"Pipeline complete. Successfully loaded {loaded_batches} batches into {table_name}.")

if __name__ == "__main__":
    main()