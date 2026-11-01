"""
Neo4j schema lineage loader — Hyrox Snowflake repo, v1.
Design notes v1.0:
  Q1 middle path: minimal vocabulary, extensible edges.
    Nodes: Table, Column, Model, Metric.
    Edges: CONTAINS, DERIVED_FROM, DEFINED_ON, FEEDS.
    Dashboard / Job nodes can be added later without renaming edges.

  Q2 simple for now: rebuild each run. MATCH (n) DETACH DELETE n.
    No incremental sync, no history preserved in v1.

  Q3 compromise with tags, all the way to bronze:
    Gold nodes: status = 'verified' (Meta analogy: signal tables).
    Bronze nodes: status = 'unverified'.
    Default queries filter to verified only; full lineage is available
    when the filter is removed.

Schema-only in v1: no athlete rows. The existing
sql/05_neo4j_graph_queries.sql athlete stub is a separate layer.
Source: dbt manifest.json + Ossie YAML in v1.1; explicit proved
models below are the v1 fallback, so the loader runs today.
Credentials: env vars only, never in code or git.
  NEO4J_URI, NEO4J_USER, NEO4J_PASSWORD
Run: python scripts/neo4j_load_schema.py
"""

import os
from pathlib import Path
from neo4j import GraphDatabase

URI = os.environ["NEO4J_URI"]
USER = os.environ["NEO4J_USER"]
PASSWORD = os.environ["NEO4J_PASSWORD"]

# status tags: 'verified' = gold / signal tier, 'unverified' = bronze / raw tier
MODELS = [
    # Bronze tier — included, tagged unverified, so lineage is complete.
    {
        "name": "hyrox_raw_season_8",
        "kind": "Table",
        "status": "unverified",
        "source": "bronze",
        "columns": ["total_time", "division"],
        "derived_from": [],
        "metrics": [],
    },
    {
        "name": "stg_hyrox_races",
        "kind": "Model",
        "status": "verified",
        "source": "silver",
        "columns": ["result_id", "division", "total_time_minutes"],
        "derived_from": ["hyrox_raw_season_8"],
        "metrics": [],
    },
    {
        "name": "pacing_obt",
        "kind": "Model",
        "status": "verified",
        "source": "gold_marketing",
        "columns": ["result_id", "division", "total_time_minutes"],
        "derived_from": ["stg_hyrox_races"],
        "metrics": [],
    },
    {
        "name": "q1_station_long",
        "kind": "Model",
        "status": "verified",
        "source": "gold_marketing",
        "columns": ["station", "transition_time"],
        "derived_from": ["pacing_obt"],
        "metrics": [],
    },
    {
        "name": "q1_station_variance",
        "kind": "Model",
        "status": "verified",
        "source": "gold_marketing",
        "columns": ["station", "transition_time_variance"],
        "derived_from": ["q1_station_long"],
        "metrics": ["transition_time_variance_elite_pro"],
    },
    {
        "name": "q2_station_degradation",
        "kind": "Model",
        "status": "verified",
        "source": "gold_marketing",
        "columns": ["division", "first_km_deviation", "station_degradation"],
        "derived_from": ["pacing_obt"],
        "metrics": ["avg_first_km_deviation", "avg_station_degradation"],
    },
]


def load_graph(tx, models):
    # Q2: rebuild, simple for now.
    tx.run("MATCH (n) DETACH DELETE n")
    for m in models:
        label = m["kind"]
        tx.run(
            f"MERGE (n:{label} {{name: $name, status: $status, source: $source}})",
            name=m["name"], status=m["status"], source=m["source"],
        )
        for col in m["columns"]:
            # Columns inherit the status of their parent node.
            tx.run(
                """
                MERGE (c:Column {name: $col, status: $status})
                MERGE (n {name: $name})
                MERGE (n)-[:CONTAINS]->(c)
                """,
                col=col, status=m["status"], name=m["name"],
            )
        for src in m["derived_from"]:
            tx.run(
                """
                MERGE (a {name: $name})
                MERGE (b {name: $src})
                MERGE (a)-[:DERIVED_FROM]->(b)
                """,
                name=m["name"], src=src,
            )
        for metric in m["metrics"]:
            tx.run(
                """
                MERGE (metric:Metric {name: $metric, status: 'verified'})
                MERGE (n {name: $name})
                MERGE (metric)-[:DEFINED_ON]->(n)
                """,
                metric=metric, name=m["name"],
            )


def main():
    manifest = Path("dbt_project/target/manifest.json")
    if manifest.exists():
        print("manifest found — v1.1 TODO: parse it and replace MODELS above")
    driver = GraphDatabase.driver(URI, auth=(USER, PASSWORD))
    with driver.session() as session:
        session.execute_write(load_graph, MODELS)
    driver.close()
    print("Schema graph rebuilt: verified gold + tagged bronze, Q1/Q2 models only.")


if __name__ == "__main__":
    main()
