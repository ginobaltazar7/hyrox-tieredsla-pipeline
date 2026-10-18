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

- Semantic models live in `dbt_project/models/semantic_models/` and are defined on gold marts.

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

- Metabase IS the frontend: it runs as its own SPCS service (`sql/deploy_metabase.sql`, public :3000); charts are hand-built in the Metabase UI against `GOLD_MARKETING.pacing_obt`. No custom frontend, no Render, no app.jsx.

- The Metabase app database (H2) does not survive an account rebuild. Dashboards are recreated by hand from the README question→chart map (Q1–Q5; Q6 excluded, no Season 7 data).

## Secrets

- Never commit `.env`. Credentials resolve from environment variables at runtime only.

- Never paste account identifiers, usernames, or passwords into issues, PRs, or docs.
