#!/usr/bin/env bash
# Finds how many users an arm can hold. Run on the load generator.
#
#   RESEED=bench-sql/reseed.sh BASE_URL=http://mint-bench-sql.dhiren.xyz k6/find-max.sh <arm>
#
# Each pass is a k6 run at N users (warm up, bench, cool down, see mint.js). A pass that
# keeps the thresholds is a pass, one that crosses them is a fail. Start at START users.
# On a pass double N until something fails. After a fail, try halfway between the last
# pass and the fail. Stop when the two are TOL users apart.
#
# RESEED is run before every pass, it cleans and seeds the database and loads the file list.
# Results go in <arm>/results/<run id>/vus-<N>/ (k6.csv.gz, summary.json, seed.csv, pass.json).
# Then common/summarize.py and common/export-search.py turn them into tables for analysis.
set -euo pipefail

ARM="${1:?usage: find-max.sh <arm>}"
: "${RESEED:?set RESEED to the script that seeds the arm}"

START="${START:-30}"
TOL="${TOL:-5}"
MAX_VUS="${MAX_VUS:-2560}"
MAX_PASSES="${MAX_PASSES:-12}"
REST_S="${REST_S:-120}"
WARMUP_S="${WARMUP_S:-120}"
BENCH_S="${BENCH_S:-300}"
COOLDOWN_S="${COOLDOWN_S:-120}"
BASE_URL="${BASE_URL:-http://mint-bench-sql.dhiren.xyz}"
RUN_ID="${RUN_ID:-$(date -u +%Y-%m-%d-%H%M)}"

HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(dirname "$HERE")"
OUT="$ROOT/$ARM/results/$RUN_ID"
mkdir -p "$OUT"

export K6_BINARY_PROVISIONING=true

# returns 0 on pass, 1 on fail, anything else is a broken run
run_pass() {
  local n="$1" dir="$OUT/vus-$1"
  mkdir -p "$dir"
  RUN_DIR="$dir" "$RESEED"

  local start end rc=0
  start=$(date -u +%s)
  k6 run -e BASE_URL="$BASE_URL" -e VUS="$n" -e WARMUP_S="$WARMUP_S" -e BENCH_S="$BENCH_S" -e COOLDOWN_S="$COOLDOWN_S" \
    --out csv="$dir/k6.csv.gz" --summary-export="$dir/summary.json" "$HERE/mint.js" || rc=$?
  end=$(date -u +%s)

  # k6 builds the extension on the first run, so take the real start from its first sample
  local first
  first=$(zcat "$dir/k6.csv.gz" 2>/dev/null | awk -F, 'NR==2{print int($2); exit}' || true)
  [ -n "$first" ] && start="$first"

  local result=broken
  [ "$rc" = 0 ] && result=pass
  [ "$rc" = 99 ] && result=fail
  cat > "$dir/pass.json" <<EOF
{"vus": $n, "result": "$result", "k6_exit": $rc, "warmup_s": $WARMUP_S, "bench_s": $BENCH_S, "cooldown_s": $COOLDOWN_S, "start": $start, "bench_start": $((start + WARMUP_S)), "bench_end": $((start + WARMUP_S + BENCH_S)), "end": $end}
EOF
  [ "$result" = pass ] && return 0
  [ "$result" = fail ] && return 1
  return 2
}

lo=0   # highest users that passed
hi=0   # lowest users that failed, 0 while nothing has failed
n="$START"

for pass in $(seq 1 "$MAX_PASSES"); do
  echo "== pass $pass: $n users (passed up to $lo, failed from $hi)"
  rc=0
  run_pass "$n" || rc=$?
  if [ "$rc" = 0 ]; then
    echo "== $n users: pass"
    lo="$n"
    if [ "$hi" = 0 ]; then
      [ "$n" -ge "$MAX_VUS" ] && { echo "== passed at the $MAX_VUS user cap, no limit found"; break; }
      n=$((n * 2))
      [ "$n" -gt "$MAX_VUS" ] && n="$MAX_VUS"
    else
      n=$(((lo + hi) / 2))
    fi
  elif [ "$rc" = 1 ]; then
    echo "== $n users: fail"
    hi="$n"
    n=$(((lo + hi) / 2))
  else
    echo "== $n users: k6 broke (see $OUT/vus-$n), stopping" >&2
    exit 1
  fi

  if [ "$hi" != 0 ] && [ $((hi - lo)) -le "$TOL" ]; then break; fi
  [ "$n" -lt 1 ] && break
  echo "== resting ${REST_S}s"
  sleep "$REST_S"
done

echo "== done: passed up to $lo users, failed from $hi"
echo "{\"arm\": \"$ARM\", \"run\": \"$RUN_ID\", \"passed_up_to\": $lo, \"failed_from\": $hi}" > "$OUT/search.json"
