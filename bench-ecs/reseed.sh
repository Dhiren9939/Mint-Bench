#!/usr/bin/env bash
# Run on the load generator, find-max.sh calls it before every pass.
# Puts the service back to its minimum task count and waits until it is stable, so a pass never starts
# on the tasks the last one scaled out. Then empties and seeds the table and loads the file list.
# Any failure stops the pass from starting.
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
[ -f "$HERE/bench.env" ] && { set -a; . "$HERE/bench.env"; set +a; }
: "${TABLE:?}" "${CLUSTER:?}" "${SERVICE:?}"
export AWS_DEFAULT_REGION="${AWS_REGION:-ap-south-1}"
MIN_TASKS="${MIN_TASKS:-2}"
COUNT="${COUNT:-10000}"
CSV="$(mktemp)"

echo "== service back to $MIN_TASKS tasks"
aws ecs update-service --cluster "$CLUSTER" --service "$SERVICE" --desired-count "$MIN_TASKS" > /dev/null
aws ecs wait services-stable --cluster "$CLUSTER" --services "$SERVICE"
running=$(aws ecs describe-services --cluster "$CLUSTER" --services "$SERVICE" --query 'services[0].runningCount' --output text)
[ "$running" = "$MIN_TASKS" ] || { echo "service has $running tasks running, expected $MIN_TASKS" >&2; exit 1; }

echo "== seeding $TABLE"
DYNAMO_TABLE="$TABLE" SEED_CSV="$CSV" python3 "$HERE/seed-dynamo.py" "$COUNT"
[ "$(wc -l < "$CSV")" -ge "$COUNT" ] || { echo "seed wrote fewer than $COUNT files" >&2; exit 1; }

"$HERE/../k6/load-file-list.sh" "$CSV"
# keep the seed next to the results when find-max.sh says where they go
[ -n "${RUN_DIR:-}" ] && cp "$CSV" "$RUN_DIR/seed.csv"
rm -f "$CSV"
