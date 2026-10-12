# CLAUDE.md — Hyrox Tiered-SLA Pipeline agent guardrails

Repo-level shared memory for any AI agent working in this repository.

The RUNBOOK covers *how to rebuild*; this file covers *how not to break things*.

## Identity & grain (do not reinterpret)

- `result_id` is the grain of every silver/gold table: `source_result_id` when present, else `res_synth_` + sha256(`event_id|name|division|total_time`).

- `athlete_id` is best-effort person identity: sha256(`name|gender|nationality|age_group`), rule v1. Mass `UNKNOWN` values signal an upstream name-normalization bug, not a data gap.

- `season` is NULLABLE. Never default missing seasons to 8. The table name `HYROX_RAW_SEASON_8` is a legacy name, not  a constraint.

- `source_result_id` is lineage only (~698K nulls observed). Never use it as a join key or grain.

## Gold ownership (unresolved — check before touching)

- Exactly ONE writer may publish `GOLD_MARKETING.pacing_obt`: either the WAP script's Publish stage (`scripts/wap_transforms.py`) or dbt's gold models but not both.

- Today dbt owns it (`pacing_obt.sql` is `SELECT * FROM stg_hyrox_races`). If WAP ever takes over, re-verify `data_contracts/hyrox_pacing_obt_contract.yaml` first.

## Ossie semantic model (do not hand-maintain)

- Never hand-edit `ossie/semantic_model.yaml` beyond AI-context annotations.

- Regenerate only from dbt semantic models: `dbt parse && ossie-dbt msi-to-ossie -i target/semantic_manifest.json -o ossie/semantic_model.yaml`

- Semantic models live in `dbt_project/models/semantic_models/` and are defined on gold marts.

## Account references (never hardcode)

- Use the `<SNOWFLAKE_ACCOUNT>` placeholder in `spcs/*.yml`, `sql/04_task_dag.sql`, and `sql/deploy_metabase.sql`. Substitute at deploy time: `sed -i "s/<SNOWFLAKE_ACCOUNT>/$SNOWFLAKE_ACCOUNT/g" spcs/*.yml sql/04_task_dag.sql sql/deploy_metabase.sql`

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
