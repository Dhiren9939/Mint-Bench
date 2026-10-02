#!/bin/bash
set -euxo pipefail
export DEBIAN_FRONTEND=noninteractive

apt-get update
apt-get install -y redis-server git jq curl gnupg ca-certificates python3-boto3 awscli

# k6 from the official apt repo
curl -fsSL https://dl.k6.io/key.gpg | gpg --dearmor -o /usr/share/keyrings/k6-archive-keyring.gpg
echo "deb [signed-by=/usr/share/keyrings/k6-archive-keyring.gpg] https://dl.k6.io/deb stable main" > /etc/apt/sources.list.d/k6.list
apt-get update
apt-get install -y k6

# Local Redis for the k6 shared code pool, bound to loopback only
sed -i 's/^bind .*/bind 127.0.0.1 -::1/; s/^protected-mode .*/protected-mode yes/' /etc/redis/redis.conf
# Every k6 user opens its own connection, the default of 10000 refuses the rest past 10000 users
echo "maxclients 60000" >> /etc/redis/redis.conf
systemctl enable redis-server
systemctl restart redis-server

# Headroom for many concurrent connections
cat > /etc/security/limits.d/99-loadgen.conf <<'LIMITS'
* soft nofile 1048576
* hard nofile 1048576
LIMITS
cat > /etc/sysctl.d/99-loadgen.conf <<'SYSCTL'
net.ipv4.ip_local_port_range = 1024 65535
net.ipv4.tcp_tw_reuse = 1
net.core.somaxconn = 65535
fs.file-max = 2097152
-net.netfilter.nf_conntrack_max = 262144
SYSCTL
sysctl --system

# CloudWatch agent: host CPU, memory and network so the generator itself can be ruled out as the bottleneck
curl -fsSL -o /tmp/cwagent.deb https://amazoncloudwatch-agent.s3.amazonaws.com/debian/amd64/latest/amazon-cloudwatch-agent.deb
dpkg -i /tmp/cwagent.deb
cat > /opt/aws/amazon-cloudwatch-agent/etc/amazon-cloudwatch-agent.json <<'CWA'
{
  "agent": { "metrics_collection_interval": 60 },
  "metrics": {
    "namespace": "MintLoadgen",
    "append_dimensions": { "InstanceId": "${aws:InstanceId}" },
    "metrics_collected": {
      "cpu": { "measurement": ["cpu_usage_user", "cpu_usage_system", "cpu_usage_idle"], "totalcpu": true },
      "mem": { "measurement": ["mem_used_percent"] },
      "net": { "measurement": ["bytes_sent", "bytes_recv"], "resources": ["*"] }
    }
  }
}
CWA
/opt/aws/amazon-cloudwatch-agent/bin/amazon-cloudwatch-agent-ctl -a fetch-config -m ec2 -s -c file:/opt/aws/amazon-cloudwatch-agent/etc/amazon-cloudwatch-agent.json

echo "loadgen ready" > /var/log/loadgen-ready