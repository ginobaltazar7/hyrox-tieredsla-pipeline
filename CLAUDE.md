# CLAUDE.md — Hyrox Tiered-SLA Pipeline agent guardrails

Repo-level shared memory for any AI agent working in this repository.

The RUNBOOK covers *how to rebuild*; this file covers *how not to break things*.

## Identity & grain (do not reinterpret)

- `result_id` is the grain of every silver/gold table: `source_result_id` when present, else `res_synth_` + sha256(`event_id|name|division|total_time`).

- `athlete_id` is best-effort person identity: sha256(`name|gender|nationality|age_group`), rule v1. Mass `UNKNOWN` values signal an upstream name-normalization bug, not a data gap.

- `season` is NULLABLE. Never default missing seasons to 8. The table name `HYROX_RAW_SEASON_8` is a legacy name, not  a constraint.

- `source_result_id` is lineage only (~698K nulls observed). Never use it as a join key or grain.

## Gold ownership (resolved 2026-10-12 — dbt owns it)

- Exactly ONE writer may publish `GOLD_MARKETING.pacing_obt`: dbt's gold models (`dbt_project/models/gold_marketing/pacing_obt.sql`, `SELECT * FROM stg_hyrox_races`).

- The WAP script's Publish stage (`scripts/wap_transforms.py`) writes its verified 7-column staging set to `GOLD_MARKETING.pacing_obt_wap_verified` — never to `pacing_obt`. Its shape (no `result_id`, no station splits) does not satisfy `data_contracts/hyrox_pacing_obt_contract.yaml`.

## Ossie semantic model (do not hand-maintain)

- Never hand-edit `ossie/semantic_model.yaml` beyond AI-context annotations.

- Regenerate only from dbt semantic models: `dbt parse && ossie-dbt msi-to-ossie -i target/semantic_manifest.json -o ossie/semantic_model.yaml`

- Semantic models live in `dbt_project/models/semantic_models.yml` and are defined on gold marts.

## dbt toolchain (the Fusion / venv trap — do not re-learn this)

- dbt Fusion 2.0.8 is a standalone binary (`~/.local/bin/dbt`), not pipx/uv-managed. Stay on 2.0.8 mid-proof.

- The MetricFlow CLI (`mf` 0.15.0) lives in the venv `~/.venvs/mf`. Installing it pulls dbt-core 1.12.6 as a dependency.

- `dbt parse/run/build` OUTSIDE the mf venv; `mf` commands INSIDE only. Activating the venv shadows Fusion: `dbt parse` inside it runs 1.12.6 and fails with a FALSE time-spine error ("semantic layer requires a time spine model with granularity DAY or smaller").

- Never add a time-spine model to fix a Fusion parse. Q1's metric has no time dimension and Fusion parses fine without one.

- All `dbt sl` commands are the dbt-Cloud platform route and fail locally with dbt1001 (no `dbt_cloud.yaml`). Local semantic-layer proof is `mf validate-configs` / `mf list metrics` / `mf query`.

- Project venvs live in `~/.venvs/<name>`, never inside the repo.

## Account references (never hardcode)

- Use the `__REGISTRY_URL__` placeholder in `spcs/*.yml`, `sql/04_task_dag.sql`, and `sql/deploy_metabase.sql`. `.github/workflows/deploy.yml` injects the `SNOWFLAKE_REGISTRY` GitHub secret at deploy time (secret value = the new account's registry hostname, e.g. `<account-identifier>.registry.snowflakecomputing.com`). Update that secret whenever the account is rebuilt.

- For manual (non-Actions) runs: `export SNOWFLAKE_REGISTRY=<registry hostname>` then `sed -i "s|__REGISTRY_URL__|$SNOWFLAKE_REGISTRY|g" spcs/*.yml sql/04_task_dag.sql sql/deploy_metabase.sql`

- On macOS, `sed -i` requires a backup suffix (`sed -i '' ...`); the GNU form above is for Linux.

## Environment variables (exact names)

- Ingestion reads `HYROX_MAX_ROWS` (0 = no cap) and `HYROX_SEASON` (table-name suffix only). The old `MAX_ROWS` name is retired and do not reintroduce it.

## Schema changes (four places, not one)

A column addition/removal/rename must land in ALL of:

1. `sql/01_setup_infrastructure.sql` (DDL — `updated_at` stays DB-generated via `DEFAULT CURRENT_TIMESTAMP()`)

2. `scripts/raw_ingest.py` (Pydantic `HyroxRecordModel`)

3. `dbt_project/models/silver/stg_hyrox_races.sql` + `dbt_project/models/schema.yml` (tests)

4. `data_contracts/hyrox_pacing_obt_contract.yaml` (bump `info.version`)

## Dashboards

- Streamlit IS the frontend: the app in `streamlit_app/` (mobile-first) runs on Render — https://hyrox-tieredsla-pipeline.onrender.com/ — verified live 2026-11-07. It reads the Q1/Q2 tables with a server-side read-only credential (key-pair auth, role `HYROX_APP_READER`); it never recomputes them. No viewer login.

- Local preview mode (`HYROX_LOCAL_DATA_DIR`) reads the preview CSVs instead of Snowflake — verify charts there before a live deploy.

- Python 3.11/3.12 only (Render uses 3.12). Altair 5 fails on Python 3.14 — keep `altair>=5,<6` and do not edit `requirements.txt` for this.

- `SNOWFLAKE_SCHEMA=RAW_BRONZE` — the gold models materialise there, not in GOLD_MARKETING.

- Metabase is no longer the frontend. `sql/deploy_metabase.sql` is legacy — do not revive it as the frontend.

- A Databricks-backed version of the same app exists in the `hyrox-databricks-port` repo (same `app.py`, Databricks `data.py`).

## Cortex Analyst demo (frozen — do not rebuild before 19 Nov)

- The demo runs from a frozen recording, not a live Snowflake session (trial ended ~10 Nov 2026). Four single-table semantic views are the demo path: `HYROX_Q1_VARIANCE_VIEW`, `HYROX_Q1_AVERAGE_VIEW`, `HYROX_Q2_VIEW`, `HYROX_Q2_CORRELATION_VIEW`.

- Source DDL: `sql/cortex_semantic_views.sql` (split views, full DDL from GET_DDL, sets its own `USE` context). `AS <sql_expr>` is required for every FACTS / DIMENSIONS / METRICS entry.

- `sql/cortex_semantic_views_combined_and_test.sql` is a superseded reference, not the demo path, so verify it against a live GET_DDL before relying on it; do not recreate from it; re-pull GET_DDL instead.

- The YAMLs in `sql/cortex/` are the view definitions as stored in Snowflake. Do not hand-edit them. `cortex-project.yaml` lists only 5 artifacts (it omits the combined view and Q1_TEST) — the DDL is authoritative, not the manifest.

- The Q1_TEST YAMLs carry a `verified_queries` block (verified question + SQL, stamped `verified_at` / `verified_by`) — ground truth for Cortex Analyst. Keep it.

## Secrets

- Never commit `.env`. Credentials resolve from environment variables at runtime only.

- Never paste account identifiers, usernames, or passwords into issues, PRs, or docs.

