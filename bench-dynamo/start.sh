#!/usr/bin/env bash
# Runs the bench-dynamo search on the load generator and prints the progress here.
# The whole search takes an hour or more and ends if your ssh session drops, so run it inside tmux,
# or set DETACH=1 to run it in the background (then tail the log).
#
#   BACKEND=admin@<backend ip> DYNAMO_TABLE=<table> bench-dynamo/start.sh
#
# The load generator has to ssh to the backend. Set SSH_KEY=<path to a key file on this box>,
# or leave it out if you connected with ssh -A.
# Any find-max.sh setting (START, TOL, BENCH_S ...) passes through.
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
[ -f "$HERE/bench.env" ] && { set -a; . "$HERE/bench.env"; set +a; }
: "${BACKEND:?}" "${DYNAMO_TABLE:?}"
AWS_REGION="${AWS_REGION:-ap-south-1}"
BASE_URL="${BASE_URL:-http://mint-bench-dynamo.dhiren.xyz}"
ROOT="$(dirname "$HERE")"
export RUN_ID="${RUN_ID:-$(date -u +%Y-%m-%d-%H%M)}"

# check everything works before spending an hour on it
code=$(curl -s -m 10 -o /dev/null -w '%{http_code}' "$BASE_URL/api/v1/file/aaaaaa" || true)
[ "$code" = 404 ] || { echo "api at $BASE_URL gave $code, expected 404" >&2; exit 1; }
SSH_OPTS=(-o StrictHostKeyChecking=accept-new -o BatchMode=yes)
[ -n "${SSH_KEY:-}" ] && SSH_OPTS+=(-i "$SSH_KEY")
ssh "${SSH_OPTS[@]}" "$BACKEND" true \
  || { echo "can't ssh to $BACKEND, set SSH_KEY to a key file or connect with ssh -A" >&2; exit 1; }
redis-cli ping > /dev/null || { echo "redis isn't running on this box" >&2; exit 1; }

mkdir -p "$ROOT/bench-dynamo/results/$RUN_ID"
LOG="$ROOT/bench-dynamo/results/$RUN_ID/run.log"

export BACKEND DYNAMO_TABLE AWS_REGION BASE_URL SSH_KEY
export RESEED="$HERE/reseed.sh"
if [ -n "${DETACH:-}" ]; then
  nohup setsid "$ROOT/k6/find-max.sh" bench-dynamo >> "$LOG" 2>&1 < /dev/null &
  echo "started run $RUN_ID in the background, log is $LOG"
  echo "it's done when $ROOT/bench-dynamo/results/$RUN_ID/search.json exists"
else
  echo "run $RUN_ID, output is also saved to $LOG"
  "$ROOT/k6/find-max.sh" bench-dynamo 2>&1 | tee -a "$LOG"
fi
echo "then run bench-dynamo/after.sh $RUN_ID on the load generator"
