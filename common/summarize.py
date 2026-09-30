#!/usr/bin/env python3
"""Turns the raw k6 output of a find-max run into tables.

  python common/summarize.py <arm> <run-id>

For every attempt (<arm>/results/<run-id>/vus-<N>/) it writes
  stats.csv     one row per phase and request name: count, rps, p50/p95/p99/avg/max in ms, failed and 5xx
  timeline.csv  10 second buckets per request name: count, p50/p95/p99, failed, 5xx and the active users
and in the run folder
  attempts.csv  the bench phase of every attempt, one row per attempt and request name

Names are upload, confirm, download, download_expired and ALL (everything together).
"""
import argparse
import csv
import glob
import gzip
import json
import math
import os
import re
from collections import defaultdict

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
PHASES = ("warmup", "bench", "cooldown")
BUCKET_S = 10


def pct(sorted_vals, p):
    if not sorted_vals:
        return ""
    return round(sorted_vals[max(0, math.ceil(p / 100 * len(sorted_vals)) - 1)], 2)


def tag(extra, key):
    m = re.search(r"(?:^|&)%s=([^&]*)" % key, extra or "")
    return m.group(1) if m else None


def open_csv(path):
    for p in (path + ".gz", path):
        if os.path.exists(p):
            return gzip.open(p, "rt", newline="") if p.endswith(".gz") else open(p, newline="")
    raise FileNotFoundError(path)


def summarize_attempt(d):
    meta = json.load(open(os.path.join(d, "pass.json")))
    warm, bench = meta.get("warmup_s", 120), meta.get("bench_s", 300)

    dur = defaultdict(list)          # (phase, name) -> ms
    failed = defaultdict(int)        # (phase, name) -> count
    errs5 = defaultdict(int)
    rates = defaultdict(lambda: [0.0, 0])   # (phase, metric) -> [sum, count]
    bdur = defaultdict(list)         # (bucket, name) -> ms
    bfail = defaultdict(int)
    berr = defaultdict(int)
    bvus = defaultdict(float)
    t0 = None

    def phase_of(t, extra):
        p = tag(extra, "phase")
        if p:
            return p
        e = t - t0
        return "warmup" if e < warm else "bench" if e < warm + bench else "cooldown"

    with open_csv(os.path.join(d, "k6.csv")) as f:
        for r in csv.DictReader(f):
            t = float(r["timestamp"])
            if t0 is None:
                t0 = t
            m, v = r["metric_name"], float(r["metric_value"])
            b = int((t - t0) // BUCKET_S) * BUCKET_S
            if m == "vus":
                bvus[b] = max(bvus[b], v)
                continue
            ph = phase_of(t, r.get("extra_tags"))
            if m in ("checks", "server_errors"):
                rates[(ph, m)][0] += v
                rates[(ph, m)][1] += 1
                continue
            name = r.get("name") or ""
            if m == "http_req_duration":
                is5 = int(r.get("status") or 0) >= 500
                for n in (name, "ALL"):
                    dur[(ph, n)].append(v)
                    bdur[(b, n)].append(v)
                    errs5[(ph, n)] += is5
                    berr[(b, n)] += is5
            elif m == "http_req_failed" and v:
                for n in (name, "ALL"):
                    failed[(ph, n)] += 1
                    bfail[(b, n)] += 1

    def rate(ph, m):
        s, c = rates[(ph, m)]
        return round(s / c, 4) if c else ""

    span = {"warmup": warm, "bench": bench, "cooldown": meta.get("cooldown_s", 120)}
    rows = []
    for ph in PHASES:
        for n in sorted({k[1] for k in dur if k[0] == ph}):
            vals = sorted(dur[(ph, n)])
            rows.append({
                "vus": meta["vus"], "result": meta["result"], "phase": ph, "name": n, "count": len(vals),
                "rps": round(len(vals) / span[ph], 2),
                "p50_ms": pct(vals, 50), "p95_ms": pct(vals, 95), "p99_ms": pct(vals, 99),
                "avg_ms": round(sum(vals) / len(vals), 2), "max_ms": round(vals[-1], 2),
                "failed": failed[(ph, n)], "failed_rate": round(failed[(ph, n)] / len(vals), 4),
                "status_5xx": errs5[(ph, n)],
                "server_error_rate": rate(ph, "server_errors"), "checks_rate": rate(ph, "checks"),
            })
    write(os.path.join(d, "stats.csv"), rows)

    tl = []
    for (b, n) in sorted(bdur):
        vals = sorted(bdur[(b, n)])
        tl.append({
            "t_s": b, "phase": "warmup" if b < warm else "bench" if b < warm + bench else "cooldown",
            "name": n, "count": len(vals), "rps": round(len(vals) / BUCKET_S, 2),
            "p50_ms": pct(vals, 50), "p95_ms": pct(vals, 95), "p99_ms": pct(vals, 99),
            "failed": bfail[(b, n)], "status_5xx": berr[(b, n)], "vus": bvus.get(b, ""),
        })
    write(os.path.join(d, "timeline.csv"), tl)
    return [r for r in rows if r["phase"] == "bench"]


def write(path, rows):
    if not rows:
        return
    with open(path, "w", newline="") as f:
        w = csv.DictWriter(f, fieldnames=list(rows[0]))
        w.writeheader()
        w.writerows(rows)


def vus_of(path):
    return int(os.path.basename(path).split("-")[1])


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("arm")
    ap.add_argument("run_id")
    a = ap.parse_args()
    run = os.path.join(ROOT, a.arm, "results", a.run_id)
    attempts = []
    for d in sorted(glob.glob(os.path.join(run, "vus-*")), key=vus_of):
        if not os.path.exists(os.path.join(d, "pass.json")):
            continue
        print("summarizing", d)
        attempts += summarize_attempt(d)
    write(os.path.join(run, "attempts.csv"), attempts)
    print("wrote", os.path.join(run, "attempts.csv"))


if __name__ == "__main__":
    main()
