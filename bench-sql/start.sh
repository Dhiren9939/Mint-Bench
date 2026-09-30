#!/usr/bin/env bash
# Starts the bench-sql search on the load generator and leaves it running in the background,
# so it keeps going if your ssh session drops. Connect with ssh -A first (see the README).
#
#   BACKEND=admin@<backend ip> DB_HOST=<rds address> DB_USERNAME=... DB_PASSWORD=... bench-sql/start.sh
#
# Any find-max.sh setting (START, TOL, BENCH_S ...) passes through.
set -euo pipefail

: "${BACKEND:?}" "${DB_HOST:?}" "${DB_USERNAME:?}" "${DB_PASSWORD:?}"
BASE_URL="${BASE_URL:-http://mint-bench-sql.dhiren.xyz}"
HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(dirname "$HERE")"
export RUN_ID="${RUN_ID:-$(date -u +%Y-%m-%d-%H%M)}"

# check everything works before spending an hour on it
code=$(curl -s -m 10 -o /dev/null -w '%{http_code}' "$BASE_URL/api/v1/file/aaaaaa" || true)
[ "$code" = 404 ] || { echo "api at $BASE_URL gave $code, expected 404" >&2; exit 1; }
ssh -o StrictHostKeyChecking=accept-new -o BatchMode=yes "$BACKEND" true \
  || { echo "can't ssh to $BACKEND, did you connect with ssh -A?" >&2; exit 1; }
redis-cli ping > /dev/null || { echo "redis isn't running on this box" >&2; exit 1; }

mkdir -p "$ROOT/bench-sql/results/$RUN_ID"
LOG="$ROOT/bench-sql/results/$RUN_ID/run.log"

export BACKEND DB_HOST DB_USERNAME DB_PASSWORD BASE_URL
export RESEED="$HERE/reseed.sh"
nohup setsid "$ROOT/k6/find-max.sh" bench-sql > "$LOG" 2>&1 < /dev/null &

echo "started run $RUN_ID"
echo "watch it:  tail -f $LOG"
echo "it's done when $ROOT/bench-sql/results/$RUN_ID/search.json exists"
echo "then run bench-sql/after.sh $RUN_ID on your machine"
