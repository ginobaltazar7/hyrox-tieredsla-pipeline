"""
Data access for the HYROX Streamlit app.

This is the only module that talks to the warehouse. The charts in app.py only
see pandas DataFrames with lowercase column names, so a Databricks version would
mainly replace this file.

Connection settings come from 7 environment variables (set on Render, never in code):
    SNOWFLAKE_ACCOUNT, SNOWFLAKE_USER, SNOWFLAKE_PRIVATE_KEY, SNOWFLAKE_ROLE,
    SNOWFLAKE_WAREHOUSE, SNOWFLAKE_DATABASE, SNOWFLAKE_SCHEMA

Local preview (development only): if HYROX_LOCAL_DATA_DIR points at a folder with
q1_station_variance.csv and q2_station_degradation.csv, the app reads those instead
of Snowflake. This is not used on Render.
"""

import os
from pathlib import Path

import pandas as pd
import streamlit as st

REQUIRED_ENV = [
    "SNOWFLAKE_ACCOUNT",
    "SNOWFLAKE_USER",
    "SNOWFLAKE_PRIVATE_KEY",
    "SNOWFLAKE_ROLE",
    "SNOWFLAKE_WAREHOUSE",
    "SNOWFLAKE_DATABASE",
    "SNOWFLAKE_SCHEMA",
]

CACHE_TTL_SECONDS = 60 * 60  # tables refresh daily; one query per table per hour at most

Q1_SQL = """
    SELECT station, transition_time_variance, n_obs
    FROM q1_station_variance
"""

Q2_SQL = """
    SELECT division, first_km_deviation, station_degradation
    FROM q2_station_degradation
"""

Q2_CORR_SQL = """
    SELECT division, n, avg_deviation, avg_degradation, corr_dev_vs_degradation
    FROM q2_deviation_correlation
"""


class DataSourceError(RuntimeError):
    """Raised with a readable message when the app cannot load its data."""


# ---------------------------------------------------------------- helpers

def _local_dir():
    path = os.getenv("HYROX_LOCAL_DATA_DIR")
    return Path(path) if path else None


def missing_env_vars():
    return [name for name in REQUIRED_ENV if not os.getenv(name)]


def _private_key_der() -> bytes:
    """Turn the PEM text in SNOWFLAKE_PRIVATE_KEY into the DER bytes the connector expects.

    Render stores multi line values fine, but if the key was pasted with literal
    \\n sequences we restore the line breaks first.
    """
    from cryptography.hazmat.primitives import serialization

    pem = os.environ["SNOWFLAKE_PRIVATE_KEY"].strip().replace("\\n", "\n")
    try:
        key = serialization.load_pem_private_key(pem.encode(), password=None)
    except Exception as exc:  # noqa: BLE001
        raise DataSourceError(
            "SNOWFLAKE_PRIVATE_KEY could not be read. It should be the full contents "
            "of rsa_key.p8, including the BEGIN and END PRIVATE KEY lines."
        ) from exc
    return key.private_bytes(
        encoding=serialization.Encoding.DER,
        format=serialization.PrivateFormat.PKCS8,
        encryption_algorithm=serialization.NoEncryption(),
    )


@st.cache_resource(show_spinner=False)
def _connection():
    import snowflake.connector

    return snowflake.connector.connect(
        account=os.environ["SNOWFLAKE_ACCOUNT"],
        user=os.environ["SNOWFLAKE_USER"],
        private_key=_private_key_der(),
        role=os.environ["SNOWFLAKE_ROLE"],
        warehouse=os.environ["SNOWFLAKE_WAREHOUSE"],
        database=os.environ["SNOWFLAKE_DATABASE"],
        schema=os.environ["SNOWFLAKE_SCHEMA"],
        client_session_keep_alive=False,
        application="hyrox_streamlit_app",
    )


def _query(sql: str) -> pd.DataFrame:
    missing = missing_env_vars()
    if missing:
        raise DataSourceError("Missing environment variables: " + ", ".join(missing))
    try:
        cur = _connection().cursor()
        try:
            cur.execute(sql)
            df = cur.fetch_pandas_all()
        finally:
            cur.close()
    except DataSourceError:
        raise
    except Exception as exc:  # noqa: BLE001
        # A cached connection can go stale; drop it so the next visit reconnects.
        _connection.clear()
        raise DataSourceError(f"Snowflake query failed: {exc}") from exc
    df.columns = [c.lower() for c in df.columns]
    return df


def _read_local(name: str) -> pd.DataFrame:
    path = _local_dir() / name
    if not path.exists():
        raise DataSourceError(f"Local preview file not found: {path}")
    df = pd.read_csv(path)
    df.columns = [c.lower() for c in df.columns]
    return df


def data_source_label() -> str:
    return "local CSV preview" if _local_dir() else "Snowflake"


# ---------------------------------------------------------------- public loaders

@st.cache_data(ttl=CACHE_TTL_SECONDS, show_spinner="Loading station data...")
def load_q1() -> pd.DataFrame:
    df = _read_local("q1_station_variance.csv") if _local_dir() else _query(Q1_SQL)
    df = df[["station", "transition_time_variance", "n_obs"]].copy()
    df["transition_time_variance"] = df["transition_time_variance"].astype(float)
    df["n_obs"] = df["n_obs"].astype(int)
    return df


@st.cache_data(ttl=CACHE_TTL_SECONDS, show_spinner="Loading pacing data...")
def load_q2() -> pd.DataFrame:
    df = _read_local("q2_station_degradation.csv") if _local_dir() else _query(Q2_SQL)
    df = df[["division", "first_km_deviation", "station_degradation"]].copy()
    df["first_km_deviation"] = df["first_km_deviation"].astype(float)
    df["station_degradation"] = df["station_degradation"].astype(float)
    return df


@st.cache_data(ttl=CACHE_TTL_SECONDS, show_spinner="Loading correlation table...")
def load_q2_correlation() -> pd.DataFrame:
    if _local_dir():
        # Local preview only: rebuild the dbt table from the per result CSV with the
        # same logic as models/gold_marketing/q2_deviation_correlation.sql.
        q2 = load_q2()

        def summarise(frame, label):
            return {
                "division": label,
                "n": len(frame),
                "avg_deviation": frame["first_km_deviation"].mean(),
                "avg_degradation": frame["station_degradation"].mean(),
                "corr_dev_vs_degradation": frame["first_km_deviation"].corr(frame["station_degradation"]),
            }

        rows = [summarise(g, d) for d, g in q2.groupby("division")]
        rows.append(summarise(q2, "ALL"))
        df = pd.DataFrame(rows)
    else:
        df = _query(Q2_CORR_SQL)
    df["n"] = df["n"].astype(int)
    for col in ["avg_deviation", "avg_degradation", "corr_dev_vs_degradation"]:
        df[col] = df[col].astype(float)
    return df
