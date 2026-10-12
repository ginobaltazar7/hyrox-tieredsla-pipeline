#!/usr/bin/env bash
#
# pipeline_healthcheck.sh — nightly pipeline health summary.
#
# Runs dbt source freshness plus the silver/gold test suites and exits non-zero
# on any failure, so a scheduler (cron, task DAG) can alert on it.
#
# Install as cron (runs 6am daily, appends to logs/healthcheck.log):
#   0 6 * * * cd /path/to/hyrox-tieredsla-pipeline && ./scripts/pipeline_healthcheck.sh >> logs/healthcheck.log 2>&1
#
# NOTE: `dbt source freshness` needs `freshness:` blocks in
# dbt_project/models/sources.yml to be meaningful — without them it reports
# "no freshness defined" and passes vacuously. Add them when the daily schedule
# goes live.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$REPO_ROOT/dbt_project"

echo "=== $(date -u +%FT%TZ) pipeline healthcheck start ==="

echo "--- dbt source freshness ---"
dbt source freshness --profiles-dir .

echo "--- dbt tests (silver, gold) ---"
dbt test --select silver gold --profiles-dir .

echo "=== $(date -u +%FT%TZ) pipeline healthcheck PASS ==="
