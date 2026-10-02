#!/usr/bin/env bash
# Runs the bench-ecs search on the load generator and prints the progress here.
# The whole search takes an hour or more and ends if your ssh session drops, so run it inside tmux,
# or set DETACH=1 to run it in the background (then tail the log).
#
#   START=1500 MAX_VUS=20000 TOL=500 THINK_JITTER=0.5 DETACH=1 bench-ecs/start.sh
#
# The settings come from bench.env (see make-env.sh). Any find-max.sh setting passes through.
# reseed.sh already puts the service back to its minimum before every pass, so there is no rest between
# passes by default. The warm up and cool down stay at the 2 minutes every arm uses, the bench phase is 8 minutes.
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
[ -f "$HERE/bench.env" ] && { set -a; . "$HERE/bench.env"; set +a; }
: "${BASE_URL:?}" "${TABLE:?}" "${CLUSTER:?}" "${SERVICE:?}"
export AWS_DEFAULT_REGION="${AWS_REGION:-ap-south-1}"
ROOT="$(dirname "$HERE")"
export RUN_ID="${RUN_ID:-$(date -u +%Y-%m-%d-%H%M)}"
export REST_S="${REST_S:-0}"
# autoscaling needs about 2 minutes to catch up, so the bench phase is 8 minutes instead of the 5 the other arms use
export BENCH_S="${BENCH_S:-480}"

# check everything works before spending an hour on it
code=$(curl -s -m 10 -o /dev/null -w '%{http_code}' "$BASE_URL/api/v1/file/aaaaaa" || true)
[ "$code" = 404 ] || { echo "api at $BASE_URL gave $code, expected 404" >&2; exit 1; }
read -r desired running < <(aws ecs describe-services --cluster "$CLUSTER" --services "$SERVICE" \
  --query 'services[0].[desiredCount,runningCount]' --output text)
[ "$desired" = "$running" ] || { echo "service has $running of $desired tasks running" >&2; exit 1; }
aws dynamodb describe-table --table-name "$TABLE" > /dev/null || { echo "can't read table $TABLE" >&2; exit 1; }
redis-cli ping > /dev/null || { echo "redis isn't running on this box" >&2; exit 1; }

mkdir -p "$ROOT/bench-ecs/results/$RUN_ID"
LOG="$ROOT/bench-ecs/results/$RUN_ID/run.log"

export BASE_URL
export RESEED="$HERE/reseed.sh"
if [ -n "${DETACH:-}" ]; then
  nohup setsid "$ROOT/k6/find-max.sh" bench-ecs >> "$LOG" 2>&1 < /dev/null &
  echo "started run $RUN_ID in the background, log is $LOG"
  echo "it's done when $ROOT/bench-ecs/results/$RUN_ID/search.json exists"
else
  echo "run $RUN_ID, output is also saved to $LOG"
  "$ROOT/k6/find-max.sh" bench-ecs 2>&1 | tee -a "$LOG"
fi
echo "then run bench-ecs/after.sh $RUN_ID on this box"
