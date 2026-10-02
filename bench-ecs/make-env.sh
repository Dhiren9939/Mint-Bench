#!/usr/bin/env bash
# Run on your machine once the backend and the load generator are up. Writes bench-ecs/bench.env from the
# Terraform outputs of the Mint repo's infra folder and copies it to the load generator.
#
#   SSH_KEY=<path to mintkey.pem> bench-ecs/make-env.sh <load generator ip>
#
# INFRA_DIR is the Mint repo's infra folder, its Terraform has to be initialised for the bench-ecs state.
set -euo pipefail

LOADGEN_IP="${1:?usage: make-env.sh <load generator ip>}"
HERE="$(cd "$(dirname "$0")" && pwd)"
INFRA_DIR="${INFRA_DIR:-$HERE/../../Mint/infra}"
out() { terraform -chdir="$INFRA_DIR" output -raw "$1"; }
members="$(terraform -chdir="$INFRA_DIR" output -json valkey_member_cluster_ids)"

cat > "$HERE/bench.env" <<ENV
BASE_URL=$(out api_url)
AWS_REGION=ap-south-1
TABLE=$(out table_name)
CLUSTER=$(out ecs_cluster)
SERVICE=$(out ecs_service)
MIN_TASKS=${MIN_TASKS:-2}
ENV_NAME=$(out env_name)
ALB=$(out alb_arn_suffix)
TG=$(out target_group_arn_suffix)
CACHE1=$(echo "$members" | jq -r '.[0]')
CACHE2=$(echo "$members" | jq -r '.[1]')
ENV
cat "$HERE/bench.env"

SSH_OPTS=(-o StrictHostKeyChecking=accept-new)
[ -n "${SSH_KEY:-}" ] && SSH_OPTS+=(-i "$SSH_KEY")
scp "${SSH_OPTS[@]}" "$HERE/bench.env" "admin@$LOADGEN_IP:Mint-Bench/bench-ecs/bench.env"
