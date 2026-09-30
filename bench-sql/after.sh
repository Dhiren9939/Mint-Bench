#!/usr/bin/env bash
# Run this on your machine once a run has finished. It makes the tables on the load generator,
# copies the results here and pulls the CloudWatch numbers for every attempt.
#
#   LOADGEN_IP=... BACKEND_ID=i-... LOADGEN_ID=i-... DB_ID=<rds identifier> bench-sql/after.sh <run-id>
#
# SSH_KEY=<path to mintkey.pem> if your key isn't already loaded. Needs the aws CLI logged in.
# Do it before tearing anything down.
set -euo pipefail

RUN="${1:?usage: after.sh <run-id>}"
: "${LOADGEN_IP:?}" "${BACKEND_ID:?}" "${LOADGEN_ID:?}" "${DB_ID:?}"

HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(dirname "$HERE")"
PY="$(command -v python3 || command -v python)"
SSH_OPTS=(-o StrictHostKeyChecking=accept-new)
[ -n "${SSH_KEY:-}" ] && SSH_OPTS+=(-i "$SSH_KEY")
REMOTE="admin@$LOADGEN_IP"
DIR="Mint-Bench/bench-sql/results/$RUN"

ssh "${SSH_OPTS[@]}" "$REMOTE" "test -f $DIR/search.json" \
  || { echo "run $RUN isn't finished yet, no search.json on the load generator. tail run.log there." >&2; exit 1; }

echo "== making the tables on the load generator"
ssh "${SSH_OPTS[@]}" "$REMOTE" "cd Mint-Bench && python3 common/summarize.py bench-sql $RUN"

echo "== copying the results"
mkdir -p "$HERE/results/$RUN"
scp -r "${SSH_OPTS[@]}" "$REMOTE:$DIR/." "$HERE/results/$RUN/"

echo "== cloudwatch, one export per attempt"
"$PY" "$ROOT/common/export-search.py" bench-sql "$RUN" --backend "$BACKEND_ID" --loadgen "$LOADGEN_ID" --db "$DB_ID"

echo "== done, everything is in $HERE/results/$RUN"
cat "$HERE/results/$RUN/search.json"
