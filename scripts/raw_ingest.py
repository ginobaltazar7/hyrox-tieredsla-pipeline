"""
    Ingest Runner Script for Hyrox Tiered SLA Pipeline
    This script fetches raw Hyrox race data, validates and transforms it, and loads it into a Snowflake Snowpark session in batches.
    It uses structured logging for telemetry and error tracking.
"""

import logging
import os
import sys
from typing import Generator, Optional
import pandas as pd
import pyarrow as pa
import pyarrow.parquet as pq
from pydantic import BaseModel, Field, ValidationError
import pyrox
from utils.sanitizers import safe_int, safe_float
from utils.session import get_snowpark_session
import hashlib

# Configure structured logging to stdout for automatic SPCS log capture and telemetry
logging.basicConfig(
    stream=sys.stdout,
    level=logging.INFO,
    format="%(asctime)s ====>> [%(levelname)s] %(name)s: %(message)s",
    datefmt="%Y-%m-%d %H:%M:%S"
)
logger = logging.getLogger("ingest-runner")

SPLIT_FIELDS = ["run1_time","run2_time","run3_time","run4_time","run5_time",
                "run6_time","run7_time","run8_time","skierg_time","sledpush_time",
                "sledpull_time","burpeebroadjump_time","rowerg_time",
                "farmerscarry_time","sandbaglunges_time","wallballs_time",
                "roxzone_time","run_time","work_time","best_run_lap"]

class HyroxRecordModel(BaseModel):
    result_id: str
    source_result_id: Optional[str] = None
    event_id: str
    athlete_id: str
    name: str
    gender: Optional[str] = None
    nationality: Optional[str] = None
    age_group: Optional[str] = None
    season: Optional[int] = None
    event_name: Optional[str] = None
    location: Optional[str] = None
    year: Optional[int] = None
    division: str
    total_time_minutes: float = Field(..., ge=0.0)
    # station splits, all optional — carried through and not coerced
    run1_time: Optional[float] = None
    run2_time: Optional[float] = None
    run3_time: Optional[float] = None
    run4_time: Optional[float] = None
    run5_time: Optional[float] = None
    run6_time: Optional[float] = None
    run7_time: Optional[float] = None
    run8_time: Optional[float] = None
    skierg_time: Optional[float] = None
    sledpush_time: Optional[float] = None
    sledpull_time: Optional[float] = None
    burpeebroadjump_time: Optional[float] = None
    rowerg_time: Optional[float] = None
    farmerscarry_time: Optional[float] = None
    sandbaglunges_time: Optional[float] = None
    wallballs_time: Optional[float] = None
    roxzone_time: Optional[float] = None
    run_time: Optional[float] = None
    work_time: Optional[float] = None
    best_run_lap: Optional[float] = None

def derive_athlete_id(name, gender, nationality, age_group) -> str:
    # Identity rule v1 (best-effort, documented). Known limitations:
    #  - age_group transitions (athlete ages up) split one human into two IDs
    #  - common name+demographics can merge two humans into one
    key = "|".join(s.strip().lower() for s in (name, gender, nationality, age_group))
    return "ath_" + hashlib.sha256(key.encode()).hexdigest()[:16]

def derive_result_id(source_result_id, event_id, name, division, total_time) -> str:
    if pd.notna(source_result_id) and str(source_result_id).strip():
        return str(source_result_id)          # prefer the source's own ID
    key = "|".join(str(v) for v in (event_id, name, division, total_time))
    return "res_synth_" + hashlib.sha256(key.encode()).hexdigest()[:16]  # deterministic fallback

def batch_generator(
        df: pd.DataFrame, 
        batch_size: int = 1000, 
        max_rows: Optional[int] = None
    ) -> Generator[pd.DataFrame, None, None]:
    total_input_rows = len(df)
    if max_rows and total_input_rows > max_rows:
        logger.warning(f"Truncating input from {total_input_rows} to {max_rows} rows (HYROX_MAX_ROWS)")
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
                name = str(row.get("name", "ANONYMOUS")).strip() if pd.notna(row.get("name")) else "ANONYMOUS"
                gender = str(row.get("gender")).strip() if pd.notna(row.get("gender")) else ""
                nationality = str(row.get("nationality")).strip() if pd.notna(row.get("nationality")) else ""
                age_group = str(row.get("age_group")).strip() if pd.notna(row.get("age_group")) else ""
                division = str(row.get("division", "OPEN")).strip() if pd.notna(row.get("division")) else "OPEN"
                event_id = str(row.get("event_id")).strip() if pd.notna(row.get("event_id")) else ""

                splits = {f: safe_float(row.get(f)) for f in SPLIT_FIELDS}

                record = HyroxRecordModel(
                    result_id=derive_result_id(row.get("source_result_id"), event_id, name, division, row.get("total_time")),
                    source_result_id=str(row.get("source_result_id")).strip() if pd.notna(row.get("source_result_id")) and str(row.get("source_result_id")).strip() else None,
                    event_id=event_id,
                    athlete_id=derive_athlete_id(name, gender, nationality, age_group),
                    name=name,
                    gender=gender or None,
                    nationality=nationality or None,
                    age_group=age_group or None,
                    division=division,
                    season=safe_int(row.get("season")) if pd.notna(row.get("season")) else None,
                    year=safe_int(row.get("year")) if pd.notna(row.get("year")) else None,
                    event_name=str(row.get("event_name")).strip() if pd.notna(row.get("event_name")) else None,
                    location=str(row.get("location", "UNKNOWN")).strip() if pd.notna(row.get("location")) else "UNKNOWN",
                    total_time_minutes=safe_float(row.get("total_time"), default=0.0),
                    **splits,
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
    max_rows = int(os.getenv("HYROX_MAX_ROWS", "0")) or None
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