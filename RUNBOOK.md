# RUNBOOK — Rebuilding the Hyrox Snowflake Environment from Code

Every database, table, and transform this pipeline needs is defined in this repo designed so nothing lives only inside a Snowflake account. So when a Snowflake trial expires or you need a fresh environment, you just need to pull the repo into Snowflake and run the steps below and you get the identical platform back in 30–45 minutes, most of it just waiting on compute.

## When to use this
- Trial has expired (account gated behind the upgrade page)
- New environment for a demo, a collaborator, or clean-room verification

## Prerequisites
1. A fresh Snowflake trial (different email than any expired trial).
2. The moment the account is created, save three things in your password manager: **account identifier**, **username**, **password**. 
3. Registry hostname for the SNOWFLAKE_REGISTRY secret: in Snowsight, + → SQL File, run SELECT CURRENT_ORGANIZATION_NAME(), CURRENT_ACCOUNT_NAME(); → the secret value is <org>-<account>.registry.snowflakecomputing.com (bare hostname — no https://, no trailing slash). Ground truth if an image repo exists: SHOW IMAGE REPOSITORIES;, copy the hostname from repository_url.
4. A `.env` file at repo root (gitignored — never commit it):

```
SNOWFLAKE_ACCOUNT=<account identifier>
SNOWFLAKE_USER=<username>
SNOWFLAKE_PASSWORD=<password>
```

## Rebuild steps
1. **Apply all code fixes first.** A freshly created account will get a properly working pipeline.
2. **Provision infrastructure:** run `sql/01_setup_infrastructure.sql` in Snowsight— database, schemas, stages, tables (single-sourced DDL).
3. **Ingest:** `python scripts/raw_ingest.py` locally (or via the dev container): `docker compose -f docker-compose.dev.yml up -d hyrox-dev`, then `docker compose exec hyrox-dev python scripts/raw_ingest.py`. Pydantic-validates and loads bronze.
4. **Transform:** `cd dbt_project && dbt run --profiles-dir . && dbt test --profiles-dir .` locally or via the dev container, prepend with `docker compose -f docker-compose.dev.yml exec hyrox-dev bash -c`
— silver/gold plus schema tests.
5. **Snapshot:** `cd dbt_project && dbt snapshot --profiles-dir .`  locally or via the dev container, prepend with `docker compose -f docker-compose.dev.yml exec hyrox-dev bash -c` — finance audit trail. If you run into errors, try `cd dbt_project && dbt clean && dbt deps && dbt snapshot --profiles-dir .`
6. **Verify:** row counts match source (~715K rows) or (~5,000 rows if capped); `athlete_id` populated (no `UNKNOWN` swarm); station-split columns present; `result_id` unique.
    - `SELECT COUNT(*) FROM SPORTS_ANALYTICS_DB.RAW_BRONZE.HYROX_RAW_SEASON_8;`
    - `SELECT sum(case when athlete_id is null then 1 else 0 end) FROM SPORTS_ANALYTICS_DB.RAW_BRONZE.HYROX_RAW_SEASON_8;`
    - 
        ```sql
            SELECT
                SUM(CASE WHEN skierg_time IS NULL THEN 1 ELSE 0 END) AS skierg_nulls, 
                SUM(CASE WHEN skierg_time = 0 THEN 1 ELSE 0 END) AS skierg_zeros,
                SUM(CASE WHEN sledpush_time IS NULL THEN 1 ELSE 0 END) AS sledpush_nulls,
                SUM(CASE WHEN sledpush_time = 0 THEN 1 ELSE 0 END) AS sledpush_zeros
            FROM SPORTS_ANALYTICS_DB.RAW_BRONZE.pacing_obt;
        ```
    - 
        ```sql
            SELECT
                count(distinct result_id) as count_result_id,
                count(*) as count
            FROM SPORTS_ANALYTICS_DB.RAW_BRONZE.pacing_obt;
        ```
7. **Operations Scheduled health checks:** `scripts/pipeline_healthcheck.sh` locally or prepend via dev container `docker compose -f docker-compose.dev.yml exec hyrox-dev bash -c `runs dbt source freshness and dbt test. Intended for cron (e.g., daily 06:00); requires dbt with a working profiles.yml. Add freshness: blocks to sources.yml to make the freshness check meaningful.
8. **Schedule (optional):** deploy SPCS images, run `sql/04_task_dag.sql` for the task chain (ingest → dbt silver → WAP gate → dbt gold → Neo4j sync). The image specs use the `__REGISTRY_URL__` placeholder — on push to `main`, `.github/workflows/deploy.yml` injects it from the `SNOWFLAKE_REGISTRY` GitHub secret (value = the account's registry hostname, e.g. `<account-identifier>.registry.snowflakecomputing.com`). **After every rebuild, update that secret to the new account's registry hostname.** For a manual run outside Actions: `export SNOWFLAKE_REGISTRY=<registry hostname> && sed -i "s|__REGISTRY_URL__|$SNOWFLAKE_REGISTRY|g" spcs/*.yml sql/04_task_dag.sql sql/deploy_metabase.sql`
9. **Redeploy Metabase (optional):** run sql/deploy_metabase.sql (specs aligned: v12, gold_marketing path), grab the endpoint with SHOW ENDPOINTS IN SERVICE ..., then rebuild the dashboards by hand in the UI — the app database doesn't survive an account rebuild, so recreate the charts from the question→chart map in the README. TODO: fix v0.55 tag, a known issue for the Metabase redeploy step.

## Coverage
- two-key identity model (`result_id` = raw grain, `athlete_id` = derived hash)
- event-level grain
- WAP audit gate that publishes only on success
- parameterized Neo4j sync for relationship graphs 
- a local docker dev loop so iteration doesn't need SPCS.
