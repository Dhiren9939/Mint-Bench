#!/usr/bin/env bash
# Cleans and seeds the Dynamo table and loads the file list. Run on the load generator, find-max.sh calls it before every pass.
# The seed runs on the backend EC2 over ssh (its role can write the table, this box has no rights on it)
# and seed.csv is copied back.
#
#   BACKEND=admin@<backend ip> DYNAMO_TABLE=<table> bench-dynamo-cache/reseed.sh
#
# ssh from the load generator to the backend needs a key. Either connect to the load generator
# with ssh -A, or copy a key onto it and set SSH_KEY=<path>.
set -euo pipefail

: "${BACKEND:?}" "${DYNAMO_TABLE:?}"
AWS_REGION="${AWS_REGION:-ap-south-1}"
COUNT="${COUNT:-10000}"
SSH_OPTS=(-o StrictHostKeyChecking=accept-new -o ServerAliveInterval=30)
[ -n "${SSH_KEY:-}" ] && SSH_OPTS+=(-i "$SSH_KEY")
HERE="$(cd "$(dirname "$0")" && pwd)"
CSV="$(mktemp)"

# copy the script over so it's always this checkout's version
scp "${SSH_OPTS[@]}" "$HERE/seed-dynamo.py" "$BACKEND:/tmp/seed-dynamo.py"
ssh "${SSH_OPTS[@]}" "$BACKEND" \
  "DYNAMO_TABLE='$DYNAMO_TABLE' AWS_REGION='$AWS_REGION' SEED_CSV=/tmp/seed.csv python3 /tmp/seed-dynamo.py $COUNT"
scp "${SSH_OPTS[@]}" "$BACKEND:/tmp/seed.csv" "$CSV"

"$HERE/../k6/load-file-list.sh" "$CSV"
# keep the seed next to the results when find-max.sh says where they go
[ -n "${RUN_DIR:-}" ] && cp "$CSV" "$RUN_DIR/seed.csv"
rm -f "$CSV"
