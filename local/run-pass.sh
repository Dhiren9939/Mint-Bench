#!/usr/bin/env bash
# One k6 pass at N users against the local stack, with the probe running and thread dumps taken mid bench.
#
#   local/run-pass.sh <users> <run-name>
#
# Restarts the api and redis first so every pass starts from the same state, then reseeds the database.
# Writes local/results/<run-name>/vus-<N>/ (k6.csv.gz, summary.json, pass.json, probe.jsonl, api.log, seed.csv).
# Same file layout as the AWS runs, so common/summarize.py works on it.
set -euo pipefail
export MSYS_NO_PATHCONV=1

N="${1:?usage: run-pass.sh <users> <run-name>}"
NAME="${2:?usage: run-pass.sh <users> <run-name>}"
WARMUP_S="${WARMUP_S:-90}"
BENCH_S="${BENCH_S:-180}"
COOLDOWN_S="${COOLDOWN_S:-30}"
DUMPS="${DUMPS:-1}"

HERE="$(cd "$(dirname "$0")" && pwd)"
OUT="$HERE/results/$NAME/vus-$N"
IN="/bench/local/results/$NAME/vus-$N"
rm -rf "$OUT"; mkdir -p "$OUT"

echo "== restarting api and redis"
docker restart mint-redis > /dev/null
until [ "$(docker inspect -f '{{.State.Health.Status}}' mint-redis)" = healthy ]; do sleep 1; done
docker restart mint-api > /dev/null
for i in $(seq 1 120); do
  code=$(curl -s -m 3 -o /dev/null -w '%{http_code}' http://localhost:18080/api/v1/file/aaaaaa || true)
  [ "$code" = 404 ] && break
  sleep 2
done
[ "$code" = 404 ] || { echo "api didn't come up" >&2; docker logs --tail 30 mint-api >&2; exit 1; }

echo "== reseeding"
docker exec -e RUN_DIR="$IN" mint-loadgen /bench/local/reseed.sh

python "$(cygpath -m "$HERE")/probe.py" "$(cygpath -m "$OUT")" &
PROBE=$!
STARTED="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

# thread dumps in the middle of the bench, printed to the container log
if [ "$DUMPS" = 1 ]; then
  ( sleep $((WARMUP_S + BENCH_S / 3)); for i in 1 2 3; do docker kill -s QUIT mint-api > /dev/null; sleep 8; done ) &
  DUMPER=$!
fi

echo "== k6, $N users: ${WARMUP_S}s warm up, ${BENCH_S}s bench, ${COOLDOWN_S}s warm down"
rc=0
docker exec mint-loadgen bash -c "cd /bench && K6_BINARY_PROVISIONING=true k6 run \
  -e BASE_URL=http://api:8080 -e VUS=$N -e WARMUP_S=$WARMUP_S -e BENCH_S=$BENCH_S -e COOLDOWN_S=$COOLDOWN_S \
  --out csv=$IN/k6.csv.gz --summary-export=$IN/summary.json k6/mint.js" || rc=$?

touch "$OUT/stop"
wait "$PROBE" || true
[ -n "${DUMPER:-}" ] && { kill "$DUMPER" 2> /dev/null || true; }
docker logs --since "$STARTED" mint-api > "$OUT/api.log" 2>&1 || true

first=$(docker exec mint-loadgen sh -c "zcat $IN/k6.csv.gz 2>/dev/null | awk -F, 'NR==2{print int(\$2); exit}'" || true)
end=$(date -u +%s)
start="${first:-$(date -u -d "$STARTED" +%s)}"
result=broken
[ "$rc" = 0 ] && result=pass
[ "$rc" = 99 ] && result=fail
cat > "$OUT/pass.json" <<EOF
{"vus": $N, "result": "$result", "k6_exit": $rc, "warmup_s": $WARMUP_S, "bench_s": $BENCH_S, "cooldown_s": $COOLDOWN_S, "start": $start, "bench_start": $((start + WARMUP_S)), "bench_end": $((start + WARMUP_S + BENCH_S)), "end": $end}
EOF
echo "== $N users: $result"
