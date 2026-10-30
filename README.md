# HYROX Tiered SLA & Performance Analytics Pipeline using Snowflake

For fans of Hyrox workouts, like my niece Isabele who is racing in November 2026 - very inspiring!  

A data engineering pipeline demonstrating a **Tiered SLA architecture** applied to endurance sports analytics using data from Hyrox! Built **100% natively inside Snowflake** using Snowpark Python Stored Procedures, Pydantic data validation, Snowpatrol Isolation Forest anomaly detection, Snowpark Container Services (SPCS) running Metabase, dbt and MetricFlow, Apache Ossie semantic models, and Neo4j knowledge graphs.

## Six Sports Analyst Questions (Tiered SLA Framework)

Tier 1: Performance & Pacing Path (Real-Time / Coaching Focus)

    1. Which functional station transition (e.g., moving from Sled Push to Burpee Broad Jumps) exhibits the highest time-loss variance across elite pro division athletes?

    2. How does an athlete's pacing deviation on the first 1km run correlate with performance degradation across the later workout stations?

    3. Which regional event location yields the fastest average transition and run speeds for doubles teams this season?

Tier 2: Official Results & Compliance Path (Audit / Financial Focus)

    4. What are the strictly verified final official podium placements and world ranking points per division after locking in all judge penalties and time adjustments?

    5. Are there any registration anomalies, duplicate IDs, or data discrepancies in the official season-end athlete ledger that impact prize-money distribution?

    6. What is the historical variance in World Championship qualification cutoff times across Seasons 7 and 8?

## Results so far

The sample behind everything below is 5,000 valid rows in
`SPORTS_ANALYTICS_DB.RAW_BRONZE.pacing_obt`, and each question was answered using separate queries.And every result was worked out three ways — hand
SQL in Snowsight, then the dbt model, then a MetricFlow query — and all
three had to agree before I called it a result.

### Q1 — Where elite and pro transitions actually vary

This question covers the elite and pro divisions together, 400 results
in total, with one row per result for each of the eight stations. Roxzone
is left out deliberately, because in the elite divisions it's missing
in a way that's perfectly systematic rather than random, and treating
that as data would just invent a story. The variance below is the
sample variance, with 400 observations behind every station:

| Station | Variance | Mean transition time |
|---|---:|---:|
| Sled Pull | 6.70 | 6.00 |
| Wall Balls | 5.61 | 5.94 |
| Sandbag Lunges | 2.86 | 4.71 |
| Burpee Broad Jump | 2.42 | 4.12 |
| Sled Push | 1.66 | 3.34 |
| Farmer's Carry | 0.33 | 2.03 |
| Row Erg | 0.26 | 4.62 |
| Ski Erg | 0.19 | 4.45 |

Sled Pull and Wall Balls are where the
best athletes separate from each other, while SkiErg and RowErg are
remarkably consistent even though their averages are high. Hyrox coaches might consider these insights to focus training on i.e. not on the stations
with the biggest averages, but on the ones where the spread is widest.

### Q2 — Starting fast, and paying for it by Wall Balls

Here the deviation is how much faster or slower an athlete's first
kilometre is than their own average run across the race, and the
degradation is simply their Wall Balls time minus their SkiErg time,
first station to last. One honest note on method: the correlation
itself is computed in hand SQL and in the dbt table, because
correlation isn't something MetricFlow offers as a metric, and I
didn't want to pretend otherwise.

| Division | n | Avg deviation | Avg degradation | Correlation |
|---|---:|---:|---:|---:|
| doubles | 2,237 | −0.93 | 0.18 | −0.16 |
| elite | 29 | −0.91 | 0.67 | −0.24 |
| elite_doubles | 29 | −0.88 | 0.21 | +0.20 |
| open | 2,363 | −1.10 | 2.49 | −0.15 |
| pro | 252 | −0.93 | 2.21 | −0.42 |
| pro_doubles | 90 | −1.11 | 0.16 | −0.48 |
| **Pooled** | **5,000** | **−1.02** | **1.37** | **−0.16** |

Based on the data, Hyrox athletes generally start about
a minute faster than their own pace, and the faster they start relative
to themselves, the more they tend to fade by Wall Balls. 

By Division, singles fade far more on average than doubles do, and pooling them
together just waters that story down. The two elite groups are also
only 29 athletes each, so their correlations carry roughly ±0.35 of
uncertainty. The elite_doubles figures don't feel conclusive. And all of
this is association, not causation: the data says these things move
together, not that one causes the other.

### Q3 and Q4 — blocked as scoped, and I'm saying so plainly

Q3 asks which location produces the fastest doubles teams this season,
but location and season are only enriched for 58 of the 5,000 rows,
with the rest sitting at location UNKNOWN and season NULL. UNKNOWN
isn't a place, and a missing season isn't "this season," so there's
no honest version of that answer from this sample yet. Q4 is in the
same position for a different reason: the sample simply has no
penalty, points, rank, verification, or podium column, so ranking
points after penalties can't be computed here — and inventing points
to fill the gap would be worse than leaving the question open.

### Q5 — the registration audit, closed on 2026-10-30

Result IDs are unique across all 5,000 rows, and source result IDs
are unique wherever they exist. The athlete-per-event probe did turn
up two pairs of athletes appearing twice in the same event and
division, which looked like duplicates at first glance, but the
row-level check settled it: each pair was two genuinely different
performances (81.00 versus 115.95 minutes, and 77.88 versus 94.08),
not the same race recorded twice, so neither row was deleted and
nothing in this probe points to a prize-money problem.

### A few rules I hold myself to on every result above

Grain is the fidelity of data cardinality, so I count joined rows
before any group-by rather than trusting the grouped output. A
missing split or run time is never treated as zero, because missing
means not recorded, not slow, and averaging it in as zero would drag
every average down for no reason. 

Doubles and relay rows count once,
as a team, not once per athlete, and a missing season is never
defaulted to anything. And one identity caveat worth stating clearly:
`athlete_id` is an attribute key, not a person — it's a hash of name,
gender, nationality, and age group, so two different athletes who
happen to share those four attributes will collide under any hash
function. 

Don't use it alone for person-level analysis, and for the
future full ingest a real person key (a source athlete ID, or a date
of birth at minimum) is a requirement, because re-hashing the same
four fields fixes nothing, and stuffing a result-specific field like
total time into the hash would break identity in the opposite
direction.

## The Business Problem: Two Teams, Two SLAs

- **Marketing / Coaching Team:** Needs hourly latency-optimized pacing metrics and real-time transition splits to power live coaching dashboards.

- **Finance / Official Race Adjudication Team:** Needs reconcilable daily batches with strict anomaly checks and penalty validation before locking in official world rankings and prize payouts.

To accommodate the SLA, the architecture splits ingestion and transformation pipelines, delivering the hourly and a verified auditable from the same source of truth without any external compute.

## Tech Stack & Native Architecture

- **Ingestion:** pre-fetched parquet (`data/hyrox_season_8.parquet`) generated via Colab validated in batches through a Pydantic generator and bulk-loaded via Snowpark Python (`scripts/raw_ingest.py`) and there is a commented `pyrox-client` block that can fetch live from the Hyrox API for non-trial accounts. The `pyrox-client` can be executed via Snowpark Python with Pydantic generator validation (`scripts/raw_ingest.py`). 

- **Transformation & Modeling:** dbt Core project (`dbt_project/`) compiling incremental silver models and gold OBT/snapshots directly inside Snowflake. Requires creation of Docker images uploaded to Snowflake repo.

- **Storage & Compute:** Snowflake warehousing, serverless task orchestration, and SPCS container pools. 

- **Governance & Quality:** Snowpatrol Isolation Forest anomaly detection acting as a WAP circuit breaker (`scripts/wap_transforms.py`). The current gate is univariate (total_time_minutes); a multivariate extension across per-division and per-station features is the next iteration.

- **Presentation Layer:** Metabase hosted natively via Snowpark Container Services (SPCS). 

- **Semantic & Graph Layer:** dbt semantic models, validated and queried with [MetricFlow](https://docs.getdbt.com/docs/build/build-metrics-intro?version=2) and exported as portable [Apache Ossie](https://github.com/apache/ossie-converters) YAML, and Snowflake-to-Neo4j graph connectors.

- **Operations:** Daily pipeline healthcheck. See [RUNBOOK.md](RUNBOOK.md).

## Native Snowflake Deployment Guide

Rebuilding after an expired trial? See [RUNBOOK.md](RUNBOOK.md) for the full account-level checklist — trial signup, credential handling, and verification.

0. **Prerequisite:** Set up Snowflake credentials: copy `.env.example` to `.env` and fill in your Snowflake account identifier, username, and password. The ingest script reads .env  from the environment (utils/session.py; warehouse, database, and schema are fixed there). `.env` is gitignored so no need to commit it.

```
    SNOWFLAKE_ACCOUNT=
    SNOWFLAKE_USER=
    SNOWFLAKE_PASSWORD=
```

Before deploying, ensure this Snowflake Git repository is fetched and synchronized:

1. **Fetch the Repo into Snowflake and run Snowflake SQL:** Pull the scripts into Snowsight and run the entire pipeline directly within Snowflake:

    ```
    ALTER GIT REPOSITORY SPORTS_ANALYTICS_DB.RAW_BRONZE.hyrox_repo FETCH;
    LS @SPORTS_ANALYTICS_DB.RAW_BRONZE.hyrox_repo/branches/main;
    SHOW GIT BRANCHES IN SPORTS_ANALYTICS_DB.RAW_BRONZE.hyrox_repo;
    ```

2. **Provision Infrastructure & Egress Rules:** Run to configure databases, schemas, compute pools, and network rules.

    `EXECUTE IMMEDIATE FROM @SPORTS_ANALYTICS_DB.RAW_BRONZE.hyrox_repo/branches/main/sql/01_setup_infrastructure.sql;` 

3. **Activate Task DAG:** Run the task dag to orchestrate automated hourly ingestion and transformation workflows.

    ```
    EXECUTE IMMEDIATE FROM @SPORTS_ANALYTICS_DB.RAW_BRONZE.hyrox_repo/branches/main/sql/04_task_dag.sql;
    EXECUTE TASK SPORTS_ANALYTICS_DB.RAW_BRONZE.task_step1_ingest;
    ```

4. **Run a Quick Select** See if there is anything in the Raw Table
   
    `SELECT * FROM SPORTS_ANALYTICS_DB.RAW_BRONZE.HYROX_RAW_SEASON_8 LIMIT 10;`


6. **Launch Metabase BI Dashboard:** Deploy the SPCS service spec `deploy_metabase.sql`, then run:
   
    `SHOW ENDPOINTS IN SERVICE SPORTS_ANALYTICS_DB.GOLD_MARKETING.metabase_service;`


<sub>Parts of this project, including documentation and analysis, were developed with assistance from Naru, an AI assistant.</sub>
