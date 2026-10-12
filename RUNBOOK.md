# RUNBOOK — Rebuilding the Hyrox Snowflake Environment from Code

Every database, table, and transform this pipeline needs is defined in this repo designed so nothing lives only inside a Snowflake account. So when a Snowflake trial expires or you need a fresh environment, you just need to pull the repo into Snowflake and run the steps below and you get the identical platform back in 30–45 minutes, most of it just waiting on compute.

## When to use this
- Trial has expired (account gated behind the upgrade page)
- New environment for a demo, a collaborator, or clean-room verification

## Prerequisites
1. A fresh Snowflake trial (different email than any expired trial).
2. The moment the account is created, save three things in your password manager: **account identifier**, **username**, **password**. 
3. A `.env` file at repo root (gitignored — never commit it):

```
SNOWFLAKE_ACCOUNT=<account identifier>
SNOWFLAKE_USER=<username>
SNOWFLAKE_PASSWORD=<password>
```

## Rebuild steps
1. **Apply all code fixes first.** A freshly created account will get a properly working pipeline.
2. **Provision infrastructure:** run `sql/01_setup_infrastructure.sql` — database, schemas, stages, tables (single-sourced DDL).
3. **Ingest:** `python scripts/raw_ingest.py` (or via the dev container: `docker compose -f docker-compose.dev.yml up -d`, then `docker compose exec hyrox-dev python scripts/raw_ingest.py`). Pydantic-validates and loads bronze.
4. **Transform:** `cd dbt_project && dbt run --profiles-dir . && dbt test --profiles-dir .` — silver/gold plus schema tests.
5. **Snapshot:** `dbt snapshot --profiles-dir .` — finance audit trail.
6. **Verify:** row counts match source (~715K rows); `athlete_id` populated (no `UNKNOWN` swarm); station-split columns present; `result_id` unique.
7. **Operations Scheduled health checks:** scripts/pipeline_healthcheck.sh runs dbt source freshness and dbt test. Intended for cron (e.g., daily 06:00); requires dbt with a working profiles.yml. Add freshness: blocks to sources.yml to make the freshness check meaningful.
8. **Schedule (optional):** deploy SPCS images, run `sql/04_task_dag.sql` for the task chain (ingest → dbt silver → WAP gate → dbt gold → Neo4j sync). And `sed -i "s/<SNOWFLAKE_ACCOUNT>/$SNOWFLAKE_ACCOUNT/g" spcs/*.yml sql/04_task_dag.sql sql/deploy_metabase.sql`
9. **Redeploy Metabase (optional):** run sql/deploy_metabase.sql (specs aligned: v12, gold_marketing path), grab the endpoint with SHOW ENDPOINTS IN SERVICE ..., then rebuild the dashboards by hand in the UI — the app database doesn't survive an account rebuild, so recreate the charts from the question→chart map in the README.

## Coverage
- two-key identity model (`result_id` = raw grain, `athlete_id` = derived hash)
- event-level grain
- WAP audit gate that publishes only on success
- parameterized Neo4j sync for relationship graphs 
- a local docker dev loop so iteration doesn't need SPCS.
