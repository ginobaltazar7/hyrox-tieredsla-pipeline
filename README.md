# HYROX Tiered SLA & Performance Analytics Pipeline using Snowflake

For fans of Hyrox workouts, a data engineering pipeline demonstrating a **Tiered SLA architecture** applied to endurance sports analytics using data from Hyrox! Built **100% natively inside Snowflake** using Snowpark Python Stored Procedures, Pydantic data validation, Snowpatrol Isolation Forest anomaly detection, Snowpark Container Services (SPCS) running Metabase, dbt, Apache Ossie semantic models, and Neo4j knowledge graphs.

## Six Sports Analyst Questions (Tiered SLA Framework)

Tier 1: Performance & Pacing Path (Real-Time / Coaching Focus)

    Which functional station transition (e.g., moving from Sled Push to Burpee Broad Jumps) exhibits the highest time-loss variance across elite pro division athletes?

    How does an athlete's pacing deviation on the first 1km run correlate with performance degradation across the later workout stations?

    Which regional event location yields the fastest average transition and run speeds for doubles teams this season?

Tier 2: Official Results & Compliance Path (Audit / Financial Focus)

    What are the strictly verified final official podium placements and world ranking points per division after locking in all judge penalties and time adjustments?

    Are there any registration anomalies, duplicate IDs, or data discrepancies in the official season-end athlete ledger that impact prize-money distribution?

    What is the historical variance in World Championship qualification cutoff times across Seasons 7 and 8?

## The Business Problem: Two Teams, Two SLAs

- **Marketing / Coaching Team:** Needs hourly latency-optimized pacing metrics and real-time transition splits to power live coaching dashboards.

- **Finance / Official Race Adjudication Team:** Needs reconcilable daily batches with strict anomaly checks and penalty validation before locking in official world rankings and prize payouts.

To accommodate the SLA, the architecture splits ingestion and  transformation pipelines, delivering the hourly and a verified auditable from the same source of truth without any external compute.

## Tech Stack & Native Architecture

- **Ingestion:** `pyrox-client` executed via Snowpark Python with Pydantic generator validation (`scripts/raw_ingest.py`). 

- **Transformation & Modeling:** dbt Core project (`dbt_project/`) compiling incremental silver models and gold OBT/snapshots directly inside Snowflake. Requires creation of Docker images uploaded to Snowflake repo.

- **Storage & Compute:** Snowflake warehousing, serverless task orchestration, and SPCS container pools. 

- **Governance & Quality:** Snowpatrol Isolation Forest anomaly detection acting as a WAP circuit breaker (`scripts/wap_transforms.py`).

- **Presentation Layer:** Metabase hosted natively via Snowpark Container Services (SPCS). 

- **Semantic & Graph Layer:** Apache Ossie portable YAML semantic models and Snowflake-to-Neo4j graph connectors.

## Native Snowflake Deployment Guide

Before deploying, ensure Snowflake Git repository is fetched and synchronized:

1. **Fetch the Repo into Snowflake and run Snowflake SQL:** Pull the scripts into Snowsight run the entire pipeline directly within Snowflake:

`ALTER GIT REPOSITORY SPORTS_ANALYTICS_DB.RAW_BRONZE.hyrox_repo FETCH;`
`LS @SPORTS_ANALYTICS_DB.RAW_BRONZE.hyrox_repo/branches/main;`
`SHOW GIT BRANCHES IN SPORTS_ANALYTICS_DB.RAW_BRONZE.hyrox_repo;`

2. **Provision Infrastructure & Egress Rules:** Run to configure databases, schemas, compute pools, and network rules.

`EXECUTE IMMEDIATE FROM @SPORTS_ANALYTICS_DB.RAW_BRONZE.hyrox_repo/branches/main/sql/01_setup_infrastructure.sql;` 

3. **Activate Task DAG:** Run the task dag to orchestrate automated hourly ingestion and transformation workflows.

`EXECUTE IMMEDIATE FROM @SPORTS_ANALYTICS_DB.RAW_BRONZE.hyrox_repo/branches/main/sql/04_task_dag.sql;`

`EXECUTE TASK SPORTS_ANALYTICS_DB.RAW_BRONZE.task_step1_ingest;`

4. **Run a Quick Select** See if there is anything in the Raw Table
`SELECT * FROM SPORTS_ANALYTICS_DB.RAW_BRONZE.HYROX_RAW_SEASON_8 LIMIT 10;`


5. **Launch Metabase BI Dashboard:** Deploy the SPCS service spec `deploy_metabase.sql`, then run: 
`SHOW ENDPOINTS IN SERVICE SPORTS_ANALYTICS_DB.GOLD_MARKETING.metabase_service; `
