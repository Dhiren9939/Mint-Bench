#!/usr/bin/env bash
# Run this on your machine after after.sh. Copies the whole run folder from the load generator into
# bench-cache-dynamo/results/<run-id>/ here, raw k6 data included (k6.csv.gz is gitignored, it stays on disk only).
#
#   LOADGEN_IP=... SSH_KEY=<path to mintkey.pem> bench-cache-dynamo/fetch.sh <run-id>
set -euo pipefail

RUN="${1:?usage: fetch.sh <run-id>}"
: "${LOADGEN_IP:?}"
HERE="$(cd "$(dirname "$0")" && pwd)"
SSH_OPTS=(-o StrictHostKeyChecking=accept-new)
[ -n "${SSH_KEY:-}" ] && SSH_OPTS+=(-i "$SSH_KEY")

mkdir -p "$HERE/results"
scp -r "${SSH_OPTS[@]}" "admin@$LOADGEN_IP:Mint-Bench/bench-cache-dynamo/results/$RUN" "$HERE/results/"
echo "copied to $HERE/results/$RUN"
du -sh "$HERE/results/$RUN"
