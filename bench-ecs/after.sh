#!/usr/bin/env bash
# Run this on the load generator once a run has finished. It pulls the CloudWatch numbers for
# every attempt into the run folder. The raw k6 data is left as it is.
#
#   bench-ecs/after.sh [run-id]        (the latest run if you leave the id out)
#
# Do it before tearing anything down.
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(dirname "$HERE")"
[ -f "$HERE/bench.env" ] && { set -a; . "$HERE/bench.env"; set +a; }
: "${CLUSTER:?}" "${SERVICE:?}" "${TABLE:?}" "${ALB:?}" "${TG:?}" "${CACHE1:?}" "${CACHE2:?}" "${ENV_NAME:?}"

RUN="${1:-$(ls -1t "$HERE/results" | head -1)}"
DIR="$HERE/results/$RUN"
[ -f "$DIR/search.json" ] || { echo "run $RUN isn't finished, no search.json in $DIR" >&2; exit 1; }

# the load generator's own instance id, from the metadata service
token=$(curl -s -X PUT http://169.254.169.254/latest/api/token -H 'X-aws-ec2-metadata-token-ttl-seconds: 60')
LOADGEN_ID="${LOADGEN_ID:-$(curl -s -H "X-aws-ec2-metadata-token: $token" http://169.254.169.254/latest/meta-data/instance-id)}"
export AWS_DEFAULT_REGION="${AWS_REGION:-ap-south-1}"

echo "== cloudwatch, one export per attempt"
python3 "$ROOT/common/export-search.py" bench-ecs "$RUN" --loadgen "$LOADGEN_ID" \
  --dim cluster="$CLUSTER" --dim service="$SERVICE" --dim table="$TABLE" --dim alb="$ALB" --dim tg="$TG" \
  --dim cache1="$CACHE1" --dim cache2="$CACHE2" --dim env="$ENV_NAME"

echo "== done, everything is in $DIR"
cat "$DIR/search.json"
echo
echo "copy it to your machine with:"
echo "  LOADGEN_IP=<this box's ip> SSH_KEY=<mintkey.pem> bench-ecs/fetch.sh $RUN"
