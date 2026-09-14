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
from utils.sanitizers import safe_int, safe_float
from utils.session import get_snowpark_session

# Configure structured logging to stdout for automatic SPCS log capture and telemetry
logging.basicConfig(
    stream=sys.stdout,
    level=logging.INFO,
    format="%(asctime)s ====>> [%(levelname)s] %(name)s: %(message)s",
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
                    athlete_id=str(row.get("athlete_id", "UNKNOWN")) if pd.notna(row.get("athlete_id")) else "UNKNOWN",
                    name=str(row.get("name", "ANONYMOUS")) if pd.notna(row.get("name")) else "ANONYMOUS",
                    season=safe_int(row.get("season"), default=8),
                    location=str(row.get("location", "UNKNOWN")) if pd.notna(row.get("location")) else "UNKNOWN",
                    total_time_minutes=safe_float(row.get("total_time"), default=0.0),
                    division=str(row.get("division", "OPEN")) if pd.notna(row.get("division")) else "OPEN"
                )
                valid_rows.append(record.model_dump())
            except ValidationError as e:
                invalid_in_batch += 1
                logger.debug(f"Validation failed for record: {e}")
                continue
        
        total_valid += len(valid_rows)
        total_invalid += invalid_in_batch
        batch_count += 1
        
        if valid_rows:
            logger.info(f"Batch {batch_count}: Processed {len(valid_rows)} valid rows ({invalid_in_batch} dropped due to validation).")
            yield pd.DataFrame(valid_rows)

    logger.info(f"Batch generation complete. Total valid rows: {total_valid}, Total dropped rows: {total_invalid}")

def main():
    session = get_snowpark_session()
    logger.info(f"Initializing Snowflake Snowpark session {session} for ingestion runner...")

    season_num = int(os.getenv("HYROX_SEASON", "8"))
    max_rows = int(os.getenv("MAX_ROWS", "5000"))
    table_name = f"hyrox_raw_season_{season_num}"


    # Uncomment to use pre-fetched parquet file generated via Colab and tracked in repository
    try:
        local_parquet_path = f"data/hyrox_season_{season_num}.parquet"
        logger.info(f"Reading pre-fetched raw data for Hyrox Season {season_num} from {local_parquet_path}...")
        if not os.path.exists(local_parquet_path):
            raise FileNotFoundError(f"====>> Pre-fetched dataset not found at {local_parquet_path}. Ensure it is committed/synced.")   
        df_raw = pd.read_parquet(local_parquet_path)
        if df_raw is None or df_raw.empty:
            logger.warning(f"No data found in local dataset for Hyrox Season {season_num}.")
        else:
            df_raw.columns = [c.lower().replace(" ", "_") for c in df_raw.columns]
            logger.info(f"Successfully loaded raw dataset containing {len(df_raw)} records.")
    except FileNotFoundError as e:
        logger.error(f"File path error: {e}")
        raise
    except Exception as e:
        logger.error(f"Unexpected error while reading local parquet file: {e}")
        raise

    """"
    # Uncomment to use fetch raw data for the specified Hyrox season using the pyrox client
    try:
        logger.info(f"Fetching raw data for Hyrox Season {season_num} via pyrox client...")
        client = pyrox.PyroxClient()
        df_raw = client.get_season(season=season_num)
        if df_raw is None or df_raw.empty:
            logger.warning(f"No data found for Hyrox Season {season_num}.")
        else:
            logger.info(f"Successfully fetched raw data for Hyrox Season {season_num}.")
            df_raw.columns = [c.lower().replace(" ", "_") for c in df_raw.columns]
    except ImportError as e:
        logger.error(f"Pyrox client not installed or failed to import: {e}")
        raise
    except AttributeError as e:
        logger.error(f"Pyrox client method or attribute mismatch: {e}")
        raise
    except ConnectionError as e:
        logger.error(f"Failed to connect to Hyrox data source: {e}")
        raise
    except Exception as e:
        logger.error(f"Unexpected error while fetching raw data: {e}")
        raise
    """
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
        session.file.put(
            file_name, 
            "@SPORTS_ANALYTICS_DB.RAW_BRONZE.ingest_stage", 
            auto_compress=False, 
            overwrite=True
        )
        
        logger.info(f"Executing bulk COPY INTO {table_name} from {file_name}...")
        session.sql(f"""
            COPY INTO {table_name}
            FROM @SPORTS_ANALYTICS_DB.RAW_BRONZE.ingest_stage/{file_name}
            FILE_FORMAT = (TYPE = PARQUET)
            MATCH_BY_COLUMN_NAME = CASE_INSENSITIVE
        """).collect()
        
        if os.path.exists(file_name):
            os.remove(file_name)
        loaded_batches += 1

    logger.info(f"Pipeline complete. Successfully loaded {loaded_batches} batches into {table_name}.")

if __name__ == "__main__":
    main()