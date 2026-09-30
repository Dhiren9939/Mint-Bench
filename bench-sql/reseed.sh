#!/usr/bin/env bash
# Cleans and seeds RDS and loads the file list. Run on the load generator, find-max.sh calls it before every pass.
# RDS is only reachable from the backend EC2, so the seed runs there over ssh and seed.csv is copied back.
#
#   BACKEND=admin@<backend ip> DB_HOST=<rds address> DB_USERNAME=... DB_PASSWORD=... bench-sql/reseed.sh
#
# ssh from the load generator to the backend needs a key. Either connect to the load generator
# with ssh -A, or copy a key onto it and set SSH_KEY=<path>.
set -euo pipefail

: "${BACKEND:?}" "${DB_HOST:?}" "${DB_USERNAME:?}" "${DB_PASSWORD:?}"
COUNT="${COUNT:-10000}"
SSH_OPTS=(-o StrictHostKeyChecking=accept-new -o ServerAliveInterval=30)
[ -n "${SSH_KEY:-}" ] && SSH_OPTS+=(-i "$SSH_KEY")
HERE="$(cd "$(dirname "$0")" && pwd)"
CSV="$(mktemp)"

ssh "${SSH_OPTS[@]}" "$BACKEND" \
  "PGHOST='$DB_HOST' PGUSER='$DB_USERNAME' PGPASSWORD='$DB_PASSWORD' PGDATABASE=mintdb \
   PGSSLMODE=verify-full PGSSLROOTCERT=/opt/mint-backend/config/global-bundle.pem \
   SEED_CSV=/tmp/seed.csv bash /opt/src/Mint-Bench/bench-sql/seed-rds.sh $COUNT"
scp "${SSH_OPTS[@]}" "$BACKEND:/tmp/seed.csv" "$CSV"

"$HERE/../k6/load-file-list.sh" "$CSV"
# keep the seed next to the results when find-max.sh says where they go
[ -n "${RUN_DIR:-}" ] && cp "$CSV" "$RUN_DIR/seed.csv"
rm -f "$CSV"
