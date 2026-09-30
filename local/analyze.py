#!/usr/bin/env python3
"""Reads the local passes of a run and prints what happened to redis and the containers during the bench.

  python local/analyze.py <run-name>

Per pass (bench window only): requests per second, latency, redis commands per request (total and per command),
new redis keys per request, redis cpu, container cpu and memory, and the fork time of the last redis save.
"""
import csv
import glob
import gzip
import json
import math
import os
import re
import sys
from collections import defaultdict

HERE = os.path.dirname(os.path.abspath(__file__))


def field(text, name):
    m = re.search(rf"^{name}:(.+)$", text, re.M)
    return float(m.group(1)) if m else None


def cmdstats(text):
    return {m.group(1): int(m.group(2)) for m in re.finditer(r"cmdstat_(\w+):calls=(\d+)", text)}


def pct(v, p):
    v = sorted(v)
    return v[max(0, math.ceil(p / 100 * len(v)) - 1)] if v else float("nan")


def first_float(s):
    m = re.match(r"\s*([\d.]+)", s or "")
    return float(m.group(1)) if m else None


def analyze(d):
    meta = json.load(open(os.path.join(d, "pass.json")))
    samples = [json.loads(l) for l in open(os.path.join(d, "probe.jsonl")) if l.strip()]
    samples = [s for s in samples if "redis" in s]
    lo, hi = meta["bench_start"], meta["bench_end"]
    win = [s for s in samples if lo <= s["ts"] <= hi]
    if len(win) < 3:
        return None
    a, b = win[0], win[-1]
    t1, t2 = a["ts"], b["ts"]

    lat, n = [], 0
    with gzip.open(os.path.join(d, "k6.csv.gz"), "rt", newline="") as f:
        for r in csv.DictReader(f):
            if r["metric_name"] != "http_req_duration":
                continue
            t = float(r["timestamp"])
            if t1 <= t <= t2:
                n += 1
                lat.append(float(r["metric_value"]))
    secs = t2 - t1

    ra, rb = a["redis"], b["redis"]
    total = field(rb["stats"], "total_commands_processed") - field(ra["stats"], "total_commands_processed")
    ca, cb = cmdstats(ra["commandstats"]), cmdstats(rb["commandstats"])
    per_cmd = {k: (cb.get(k, 0) - ca.get(k, 0)) for k in cb}
    cpu = (field(rb["cpu"], "used_cpu_sys") + field(rb["cpu"], "used_cpu_user")
           - field(ra["cpu"], "used_cpu_sys") - field(ra["cpu"], "used_cpu_user")) / secs * 100
    keys = int(rb["dbsize"] or 0) - int(ra["dbsize"] or 0)

    cont = defaultdict(list)
    mem = defaultdict(list)
    for s in win:
        for row in s["docker"]:
            cont[row["Name"]].append(first_float(row["CPUPerc"]))
            mem[row["Name"]].append(first_float(row["MemUsage"]))

    out = {
        "vus": meta["vus"], "result": meta["result"], "requests": n, "rps": n / secs,
        "p50": pct(lat, 50), "p95": pct(lat, 95), "p99": pct(lat, 99),
        "redis_cmds_per_req": total / n if n else float("nan"),
        "redis_cmds_per_sec": total / secs,
        "new_keys_per_req": keys / n if n else float("nan"),
        "redis_cpu_pct": cpu,
        "top_cmds": sorted(((k, v / n) for k, v in per_cmd.items() if v > 0), key=lambda kv: -kv[1])[:6] if n else [],
        "cpu": {k: sum(v) / len(v) for k, v in cont.items()},
        "mem_mb": {k: sum(v) / len(v) for k, v in mem.items()},
        "fork_usec": field(rb["stats"], "latest_fork_usec") or 0,
        "dbsize_end": rb["dbsize"],
    }
    return out


def main():
    run = os.path.join(HERE, "results", sys.argv[1])
    dirs = sorted(glob.glob(os.path.join(run, "vus-*")), key=lambda p: int(p.rsplit("-", 1)[1]))
    lines = []
    for d in dirs:
        try:
            r = analyze(d)
        except FileNotFoundError:
            continue
        if not r:
            continue
        lines.append(
            f"{r['vus']:>5} users {r['result']:<6} {r['rps']:6.0f} req/s  p50 {r['p50']:7.1f}  p95 {r['p95']:8.1f}  p99 {r['p99']:8.1f} ms\n"
            f"        redis: {r['redis_cmds_per_req']:.2f} commands/request ({r['redis_cmds_per_sec']:.0f}/s), {r['new_keys_per_req']:.3f} new keys/request, "
            f"cpu {r['redis_cpu_pct']:.0f}% of a core, fork {r['fork_usec']:.0f} us, {r['dbsize_end']} keys at the end\n"
            f"        per request: " + ", ".join(f"{k} {v:.2f}" for k, v in r["top_cmds"]) + "\n"
            f"        container cpu% (100 = one core): " + ", ".join(f"{k.replace('mint-', '')} {v:.0f}" for k, v in sorted(r["cpu"].items())) + "\n"
            f"        container mem MB: " + ", ".join(f"{k.replace('mint-', '')} {v:.0f}" for k, v in sorted(r["mem_mb"].items()))
        )
    text = "\n".join(lines)
    print(text)
    with open(os.path.join(run, "analysis.txt"), "w") as f:
        f.write(text + "\n")


if __name__ == "__main__":
    main()
