#!/usr/bin/env bash
# Runs inside the loadgen container. Cleans and seeds the database, loads the file list into the local redis.
set -euo pipefail

redis-cli ping > /dev/null 2>&1 || { redis-server --daemonize yes --save "" --appendonly no > /dev/null; sleep 1; }

CSV=/tmp/seed.csv
PGHOST=postgres PGUSER=mintadmin PGPASSWORD=bench PGDATABASE=mintdb SEED_CSV="$CSV" \
  bash /bench/bench-sql/seed-rds.sh "${COUNT:-10000}" > /tmp/seed.log 2>&1 || { cat /tmp/seed.log; exit 1; }

/bench/k6/load-file-list.sh "$CSV"
[ -n "${RUN_DIR:-}" ] && cp "$CSV" "$RUN_DIR/seed.csv"
exit 0
