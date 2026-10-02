#!/usr/bin/env bash
# Folds the finished attempts of one run into another run of the same arm, so a search that was stopped
# and started again reads as one run. Run it on the load generator once the target run is done.
#
#   common/merge-run.sh <arm> <from-run> <to-run>
#
# Only attempts that have a pass.json are copied (an attempt that was stopped half way has none).
# An attempt the target already has is left alone. The source run is not touched.
# search.json of the target is worked out again from every attempt it now holds.
# The copied attempts keep their own bench length, it's in their pass.json, so check it before comparing.
set -euo pipefail

ARM="${1:?usage: merge-run.sh <arm> <from-run> <to-run>}"
FROM="${2:?}"
TO="${3:?}"
HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(dirname "$HERE")"
SRC="$ROOT/$ARM/results/$FROM"
DST="$ROOT/$ARM/results/$TO"
[ -d "$SRC" ] || { echo "no run $FROM in $ARM" >&2; exit 1; }
[ -f "$DST/search.json" ] || { echo "run $TO isn't finished, no search.json in $DST" >&2; exit 1; }

for dir in "$SRC"/vus-*; do
  name="$(basename "$dir")"
  if [ ! -f "$dir/pass.json" ]; then echo "skip $name: no pass.json (stopped half way)"; continue; fi
  if [ -e "$DST/$name" ]; then echo "skip $name: $TO already has it"; continue; fi
  cp -a "$dir" "$DST/$name"
  echo "copied $name from $FROM ($(jq -r '"\(.result), bench \(.bench_s)s"' "$dir/pass.json"))"
  echo "$FROM" > "$DST/$name/merged-from.txt"
done

# highest pass that sits below the lowest fail, 0 for none, same as find-max.sh keeps them
jq -s --arg arm "$ARM" --arg run "$TO" '
  (map(select(.result == "fail") | .vus) | min // 0) as $hi
  | {arm: $arm, run: $run,
     passed_up_to: (map(select(.result == "pass" and ($hi == 0 or .vus < $hi)) | .vus) | max // 0),
     failed_from: $hi}' "$DST"/vus-*/pass.json > "$DST/search.json.new"
mv "$DST/search.json.new" "$DST/search.json"
echo "search.json: $(cat "$DST/search.json")"
echo "now run $ARM/after.sh $TO to export CloudWatch for the copied attempts too"
