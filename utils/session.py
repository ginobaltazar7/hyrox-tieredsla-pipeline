import os
import logging
from snowflake.snowpark import Session

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def get_snowpark_session() -> Session:
    if os.path.exists("/snowflake/session/token"):
        logger.info("Detecting SPCS container environment; initializing session with internal OAuth token.")
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
        logger.info("Local environment detected; initializing session with credential-based configuration.")
        return Session.builder.configs({
            "account": os.getenv("SNOWFLAKE_ACCOUNT"),
            "user": os.getenv("SNOWFLAKE_USER"),
            "password": os.getenv("SNOWFLAKE_PASSWORD"),
            "warehouse": "COMPUTE_WH",
            "database": "SPORTS_ANALYTICS_DB",
            "schema": "RAW_BRONZE"
        }).create()