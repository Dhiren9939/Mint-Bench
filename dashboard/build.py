#!/usr/bin/env python3
"""Builds one HTML dashboard for a find-max run. Works for any arm, it only reads the shared result files.

  python common/summarize.py <arm> <run-id>     # once, makes stats.csv and timeline.csv from the raw data
  python dashboard/build.py <arm> <run-id>

Writes <arm>/results/<run-id>/dashboard.html, one file with the data inside, open it in a browser.
"""
import argparse
import csv
import json
import os
from datetime import datetime

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)

# what goes in the dashboard, everything else in metrics.csv is left out
KEEP = {
    "backend": {
        "cpu_usage_user", "cpu_usage_system", "cpu_usage_steal", "mem_used_percent", "swap_used_percent",
        "procstat_cpu_usage", "procstat_memory_rss", "netstat_tcp_established",
    },
    "loadgen": {"cpu_usage_user", "cpu_usage_system", "mem_used_percent"},
    "db": {"CPUUtilization", "DatabaseConnections", "WriteIOPS", "ReadIOPS", "FreeableMemory"},
}
PROCESSES = {"java", "redis-server", "dockerd", "containerd", "amazon-cloudwatch-agent"}


def rows(path):
    with open(path, newline="") as f:
        return list(csv.DictReader(f))


def num(v):
    try:
        return round(float(v), 3)
    except (TypeError, ValueError):
        return None


def keep_series(r):
    if r["metric"] not in KEEP.get(r["source"], ()):
        return False
    if r["namespace"] == "AWS/EC2":
        return False
    if r["metric"].startswith("procstat"):
        return r["dims"] in {f"exe={p};process_name={p}" for p in PROCESSES}
    return True


def attempt(d):
    meta = json.load(open(os.path.join(d, "pass.json")))
    start = meta["start"]

    timeline = {}
    for r in rows(os.path.join(d, "timeline.csv")):
        t = timeline.setdefault(r["name"], {k: [] for k in ("t", "rps", "p50", "p95", "p99", "failed", "vus")})
        t["t"].append(int(r["t_s"]))
        for k, col in (("rps", "rps"), ("p50", "p50_ms"), ("p95", "p95_ms"), ("p99", "p99_ms"),
                       ("failed", "failed"), ("vus", "vus")):
            t[k].append(num(r[col]))

    metrics = {}
    for r in rows(os.path.join(d, "metrics.csv")):
        if not keep_series(r):
            continue
        key = "|".join((r["source"], r["metric"], r["dims"], r["stat"]))
        t = datetime.fromisoformat(r["timestamp"]).timestamp() - start
        metrics.setdefault(key, []).append([round(t), num(r["value"])])
    for v in metrics.values():
        v.sort()

    return {
        "vus": meta["vus"], "result": meta["result"], "start": start,
        "warmup_s": meta["warmup_s"], "bench_s": meta["bench_s"], "cooldown_s": meta["cooldown_s"],
        "stats": rows(os.path.join(d, "stats.csv")),
        "timeline": timeline,
        "metrics": metrics,
    }


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("arm")
    ap.add_argument("run_id")
    a = ap.parse_args()

    run = os.path.join(ROOT, a.arm, "results", a.run_id)
    attempts = []
    for name in sorted(os.listdir(run)):
        d = os.path.join(run, name)
        if name.startswith("vus-") and os.path.exists(os.path.join(d, "timeline.csv")):
            attempts.append(attempt(d))
    attempts.sort(key=lambda x: x["start"])
    for i, x in enumerate(attempts, 1):
        x["order"] = i

    data = {"arm": a.arm, "run": a.run_id, "search": json.load(open(os.path.join(run, "search.json"))),
            "attempts": attempts}
    html = open(os.path.join(HERE, "template.html"), encoding="utf-8").read()
    html = html.replace("__DATA__", json.dumps(data, separators=(",", ":")).replace("</", "<\\/"))
    out = os.path.join(run, "dashboard.html")
    with open(out, "w", encoding="utf-8") as f:
        f.write(html)
    print(f"wrote {out} ({len(html) // 1024} kB, {len(attempts)} attempts)")


if __name__ == "__main__":
    main()
