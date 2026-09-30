#!/usr/bin/env python3
"""Samples the local containers and the backend's redis every couple of seconds, until <outdir>/stop exists.

  python local/probe.py <outdir>

Writes <outdir>/probe.jsonl, one line per sample: {"ts", "docker": [docker stats rows], "redis": {...raw INFO text...}}.
"""
import json
import os
import subprocess
import sys
import time

CONTAINERS = ["mint-api", "mint-redis", "mint-pg", "mint-loadgen"]
INTERVAL_S = 2.0


def run(cmd):
    return subprocess.run(cmd, capture_output=True, text=True, timeout=20).stdout


def main():
    out = sys.argv[1]
    stop = os.path.join(out, "stop")
    with open(os.path.join(out, "probe.jsonl"), "w") as f:
        while not os.path.exists(stop):
            t0 = time.time()
            try:
                stats = [json.loads(l) for l in run(["docker", "stats", "--no-stream", "--format", "{{json .}}", *CONTAINERS]).splitlines() if l.strip()]
                redis = {
                    "stats": run(["docker", "exec", "mint-redis", "redis-cli", "INFO", "stats"]),
                    "cpu": run(["docker", "exec", "mint-redis", "redis-cli", "INFO", "cpu"]),
                    "commandstats": run(["docker", "exec", "mint-redis", "redis-cli", "INFO", "commandstats"]),
                    "persistence": run(["docker", "exec", "mint-redis", "redis-cli", "INFO", "persistence"]),
                    "dbsize": run(["docker", "exec", "mint-redis", "redis-cli", "--raw", "DBSIZE"]).strip(),
                }
                f.write(json.dumps({"ts": t0, "docker": stats, "redis": redis}) + "\n")
                f.flush()
            except Exception as e:  # a slow docker call must not stop the run
                f.write(json.dumps({"ts": t0, "error": str(e)}) + "\n")
            time.sleep(max(0.0, INTERVAL_S - (time.time() - t0)))


if __name__ == "__main__":
    main()
