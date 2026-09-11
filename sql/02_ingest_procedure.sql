-- Description: Bundles the Pydantic validation schema and a generator workflow directly into a Snowflake Python Stored Procedure.
SQL
CREATE OR REPLACE PROCEDURE SPORTS_ANALYTICS_DB.RAW_BRONZE.sp_ingest_hyrox(season_num INT)
RETURNS STRING
LANGUAGE PYTHON
RUNTIME_VERSION = '3.10'
PACKAGES = ('snowflake-snowpark-python', 'pandas', 'pydantic', 'pyrox-client')
EXTERNAL_ACCESS_INTEGRATIONS = (pyrox_external_access_integration)
HANDLER = 'ingest_handler'
AS
$$
from typing import Generator
import pandas as pd
from pydantic import BaseModel, Field, ValidationError
import pyrox
from snowflake.snowpark import Session

class HyroxRecordModel(BaseModel):
    athlete_id: str = Field(..., description="Unique athlete identifier")
    name: str
    season: int
    location: str
    total_time_minutes: float = Field(..., ge=0.0)
    division: str

def batch_generator(df: pd.DataFrame, batch_size: int = 1000) -> Generator[pd.DataFrame, None, None]:
    for i in range(0, len(df), batch_size):
        batch_df = df.iloc[i:i+batch_size].copy()
        valid_rows = []
        for _, row in batch_df.iterrows():
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
            except ValidationError:
                continue
        if valid_rows:
            yield pd.DataFrame(valid_rows)

def ingest_handler(session: Session, season_num: int) -> str:
    client = pyrox.PyroxClient()
    df_raw = client.get_season(season=season_num)
    df_raw.columns = [c.lower().replace(" ", "_") for c in df_raw.columns]
    
    table_name = f"hyrox_raw_season_{season_num}"
    first_batch = True
    for batch_df in batch_generator(df_raw):
        session.write_pandas(batch_df, table_name=table_name, database="SPORTS_ANALYTICS_DB", schema="RAW_BRONZE", auto_create_table=True, overwrite=first_batch)
        first_batch = False
    return f"Successfully ingested Season {season_num} into RAW_BRONZE.{table_name}"
$$;
