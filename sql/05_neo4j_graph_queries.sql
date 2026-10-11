-- Description: Executes graph queries directly through Snowflake SQL stored procedure connectors to analyze athlete station transitions and relationships.
-- Graph should only ever contain WAP verified records, as the WAP gate is a prerequisite for any graph ingestion.
-- TODO: Extend sp_sync_neo4j_graph's UNWIND to MERGE per-split Station nodes,
--   e.g. (a)-[:RAN {time_mins: row.run1_time}]->(:Station {name: 'Run 1'}),
--   so the graph can answer analyst Q1 (transition variance) and Q2 (pacing
--   degradation). Requires: Item 1 station splits flowing through gold.


CREATE OR REPLACE PROCEDURE SPORTS_ANALYTICS_DB.RAW_BRONZE.sp_sync_neo4j_graph()
RETURNS VARCHAR
LANGUAGE PYTHON
RUNTIME_VERSION = '3.11'
PACKAGES = ('snowflake-snowpark-python')
HANDLER = 'main'
AS
$$
def main(session):
    rows = session.sql("""
        SELECT athlete_id, name, event_id, location, season,
               division, total_time_minutes, updated_at
        FROM SPORTS_ANALYTICS_DB.GOLD_MARKETING.pacing_obt
    """).to_pandas().to_dict("records")
    # batch rows -> CALL NEO4J_GRAPH_APP.PUBLIC.EXECUTE_CYPHER with the UNWIND/MERGE
    ...
    return f"synced {len(rows)} rows"
$$;
