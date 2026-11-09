# RUNBOOK — Rebuilding the Hyrox Snowflake Environment from Code

Everything this pipeline needs i.e. database, table, and transform, lives in this repo as code, not just inside a Snowflake account. So if a Snowflake trial expires, or you need a fresh environment for a demo or a clean check, you pull this repo into Snowflake, run the steps below, and you get the same platform back in about 30 to 45 minutes. Most of that time is just waiting on the compute to finish.

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
0. **Check your Snowflake account first:** In Snowsight, run `SELECT CURRENT_ORGANIZATION_NAME(), CURRENT_ACCOUNT_NAME(), CURRENT_ROLE();` and confirm they match the account and role you're deploying with. Do not use `CURRENT_ACCOUNT()` alone for this check — it returns the account locator, not the account name.
1. **Pull the latest repo first.** A freshly created account will get a properly working pipeline.
2. **Provision infrastructure:** run `sql/01_setup_infrastructure.sql` in Snowsight— database, schemas, stages, tables (single-sourced DDL).
3. **Ingest:** `python scripts/raw_ingest.py` locally (or via the dev container): `docker compose -f docker-compose.dev.yml up -d hyrox-dev`, then `docker compose exec hyrox-dev python scripts/raw_ingest.py`. Pydantic-validates and loads bronze.
4. **Transform:** Run dbt **outside** the MetricFlow venv, with dbt Fusion 2.0.8 — never inside `~/.venvs/mf`. The venv's dbt-core 1.12.6 shadows Fusion and fails with a false time-spine error. `mf` commands go inside the venv only. Copy the template at `dbt/profiles.yml` to `~/.dbt/profiles.yml` and fill in your own values first, if you haven't already.
    `cd dbt_project && dbt run --profiles-dir ~/.dbt && dbt test --profiles-dir ~/.dbt` locally, or via the dev container: `docker compose -f docker-compose.dev.yml exec hyrox-dev bash -c "cd dbt_project && dbt run --profiles-dir ~/.dbt && dbt test --profiles-dir ~/.dbt"` — silver/gold plus schema tests.
5. **Snapshot:** `cd dbt_project && dbt snapshot --profiles-dir ~/.dbt` locally, or via the dev container: `docker compose -f docker-compose.dev.yml exec hyrox-dev bash -c "cd dbt_project && dbt snapshot --profiles-dir ~/.dbt"` — finance audit trail. If you run into errors, try `cd dbt_project && dbt clean && dbt deps && dbt snapshot --profiles-dir ~/.dbt`
6. **Verify:** row counts match — 5,000 rows by default (the ingest script caps at 5,000), or ~715K rows if you lifted the cap first; `athlete_id` populated (no nulls, no `UNKNOWN` swarm); station-split columns present; `result_id` unique.
    - `SELECT COUNT(*) FROM SPORTS_ANALYTICS_DB.RAW_BRONZE.HYROX_RAW_SEASON_8;`
    - `SELECT sum(case when athlete_id is null then 1 else 0 end) FROM SPORTS_ANALYTICS_DB.RAW_BRONZE.HYROX_RAW_SEASON_8;`
    - `SELECT sum(case when athlete_id = 'UNKNOWN' then 1 else 0 end) FROM SPORTS_ANALYTICS_DB.RAW_BRONZE.HYROX_RAW_SEASON_8;`
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
7. **Operations Scheduled health checks:** Run `scripts/pipeline_healthcheck.sh` locally, or via the dev container: `docker compose -f docker-compose.dev.yml exec hyrox-dev bash -c "scripts/pipeline_healthcheck.sh"` — runs dbt source freshness and dbt test. Intended for cron (e.g., daily 06:00) and requires dbt with a working profiles.yml. Add freshness limits to `sources.yml` first, e.g. to warn if the data is more than a day old. Without those limits, the freshness check will pass even when the data is stale.
8. **Schedule the task chain (optional):** This sets up the automatic run: ingest → dbt silver → dbt gold → Neo4j sync. Run sql/04_task_dag.sql. The WAP gate sits outside the dbt DAG by design: data is written unverified first and promoted to `pacing_obt_wap_verified` only if the audit passes.
    - **How the images get their address:** the SPCS specs use a placeholder, __REGISTRY_URL__. On a push to main, GitHub Actions fills it in from the SNOWFLAKE_REGISTRY secret — that's your account's registry hostname, e.g. <org>-<account>.registry.snowflakecomputing.com.
    - **After every rebuild, update that secret.** A new account means a new registry hostname, so the old secret will point at the old account.
    - **If you're running it by hand, outside Actions:** set the hostname yourself first, then replace the placeholder in the files: 

    ```
    export SNOWFLAKE_REGISTRY=<registry hostname>
    sed -i "s|__REGISTRY_URL__|$SNOWFLAKE_REGISTRY|g" spcs/*.yml sql/04_task_dag.sql

    ```
    Run the `sed` command in the dev container (GNU sed). On macOS, `sed -i` needs a backup suffix, e.g. `sed -i ''`.
9. **Presentation — Streamlit on Render.** The app lives in streamlit_app/ and runs on Render — see the README, "Recreate this deployment from scratch". 

## What this pipeline covers
- **Identity has two keys:** Every result has its own `result_id`, and every athlete gets an `athlete_id` built from their details. That's how we tell results and people apart.
- **Grain fidelity:** One row per result, per event, the grain that everything else is built on.
- **A safety gate for trustworthiness:** A WAP audit has to pass before data is marked verified. Bad data stays out of the verified tables.
- **Graph sync from an explicit list:** The Neo4j loader rebuilds the schema graph from a fixed list of models in the `scripts/neo4j_load_schema.py` script, i.e.Q1/Q2 only, bronze tagged unverified, gold tagged verified. Credentials come from env vars, and not from code. TODO: Parsing the dbt manifest instead is a v1.1 job.
- **A local Docker loop for day-to-day work:** You can build and test locally, without needing Snowpark Container Services.

<sub>Parts of this project, including documentation and analysis, were developed with assistance from Naru, an AI assistant.</sub>