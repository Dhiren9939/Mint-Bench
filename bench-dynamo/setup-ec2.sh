#!/usr/bin/env bash
# Sets up the bench-dynamo backend EC2 (Debian). The Mint infra runs this from user data,
# but you can also run it by hand on the box to retry.
# Needs the Mint and Mint-Bench checkouts, MINT_DIR and BENCH_DIR say where they are
# (user data puts them in /opt/src).
#
#   DYNAMO_TABLE=<table name> AWS_REGION=ap-south-1 ./setup-ec2.sh
#
# The table is made by terraform and the box's instance role can read and write it, so there are no keys here.
set -euo pipefail

: "${DYNAMO_TABLE:?}"
AWS_REGION="${AWS_REGION:-ap-south-1}"
MINT_DIR="${MINT_DIR:-$HOME/Mint}"
BENCH_DIR="${BENCH_DIR:-$HOME/Mint-Bench}"
CONFIG_DIR=/opt/mint-backend/config
IMAGE=mint-backend:bench

# 1gb of ram isn't enough to build the image
if ! swapon --show | grep -q /swapfile; then
  sudo fallocate -l 2G /swapfile
  sudo chmod 600 /swapfile
  sudo mkswap /swapfile
  sudo swapon /swapfile
  echo '/swapfile none swap sw 0 0' | sudo tee -a /etc/fstab
fi

# htop is for watching the box live over ssh, boto3 is for reseed.sh
sudo apt-get update
sudo apt-get install -y ca-certificates curl htop python3-boto3

# docker
sudo install -m 0755 -d /etc/apt/keyrings
sudo curl -fsSL https://download.docker.com/linux/debian/gpg -o /etc/apt/keyrings/docker.asc
sudo chmod a+r /etc/apt/keyrings/docker.asc
sudo tee /etc/apt/sources.list.d/docker.sources > /dev/null <<EOF
Types: deb
URIs: https://download.docker.com/linux/debian
Suites: $(. /etc/os-release && echo "$VERSION_CODENAME")
Components: stable
Architectures: $(dpkg --print-architecture)
Signed-By: /etc/apt/keyrings/docker.asc
EOF
sudo apt-get update
sudo apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
sudo systemctl enable --now docker

# cloudwatch agent, same config on every arm
curl -fsSL -o /tmp/cwagent.deb https://amazoncloudwatch-agent.s3.amazonaws.com/debian/amd64/latest/amazon-cloudwatch-agent.deb
sudo dpkg -i /tmp/cwagent.deb
sudo cp "$BENCH_DIR/common/cwagent.json" /opt/aws/amazon-cloudwatch-agent/etc/amazon-cloudwatch-agent.json
sudo /opt/aws/amazon-cloudwatch-agent/bin/amazon-cloudwatch-agent-ctl -a fetch-config -m ec2 -s \
  -c file:/opt/aws/amazon-cloudwatch-agent/etc/amazon-cloudwatch-agent.json

# config the container mounts
sudo mkdir -p $CONFIG_DIR
sudo cp "$MINT_DIR"/backend/config/*.properties "$MINT_DIR/backend/docker-compose.prod.yml" $CONFIG_DIR
sudo chmod -R 755 /opt/mint-backend

# build on the box, then drop the build cache so the 8gb disk doesn't fill up
sudo docker build -t $IMAGE "$MINT_DIR/backend"
sudo docker builder prune -af

sudo -E env IMAGE_TAG=$IMAGE DYNAMO_TABLE="$DYNAMO_TABLE" AWS_REGION="$AWS_REGION" \
  docker compose -f $CONFIG_DIR/docker-compose.prod.yml -f "$BENCH_DIR/bench-dynamo/compose.override.yml" up -d

# a file code that doesn't exist should come back as a 404 (that also proves the role can read the table)
for i in $(seq 1 30); do
  code=$(curl -s -o /dev/null -w '%{http_code}' http://localhost/api/v1/file/aaaaaa || true)
  [ "$code" = 404 ] && { echo "api is up"; exit 0; }
  sleep 5
done
echo "api didn't come up, last status $code"
sudo docker compose -f $CONFIG_DIR/docker-compose.prod.yml logs --tail 50 api
exit 1
