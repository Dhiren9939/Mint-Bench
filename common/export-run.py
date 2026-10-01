#!/usr/bin/env python3
"""Export the CloudWatch metrics for one run to <arm>/results/<run-id>/metrics.csv

Every arm gets the same csv columns:
    timestamp,source,namespace,metric,dims,stat,value
source is backend, loadgen or db. Which metrics get exported comes from common/queries.json
and <arm>/queries.json, so an arm without an RDS just has no db rows.

python common/export-run.py bench-sql 2026-10-01-a \
    --start 2026-10-01T10:00:00Z --end 2026-10-01T11:00:00Z \
    --backend i-0123 --loadgen i-0456 --db mydbidentifier

Needs the aws cli logged in. Copy the k6 output (k6.csv, summary.json) into the same folder yourself.
"""
import argparse
import csv
import json
import os
import subprocess
import sys
import tempfile

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
STATS = ["Average", "Maximum"]
PERIOD = 60
BATCH = 400  # get-metric-data takes 500 queries at most


def aws(*args):
    out = subprocess.run(["aws", *args, "--output", "json"], check=True, capture_output=True, text=True).stdout
    return json.loads(out) if out.strip() else {}


def load(path):
    with open(path) as f:
        return json.load(f)


def discover(spec, values):
    dims = {k: v.format(**values) for k, v in spec["dimensions"].items()}
    args = ["cloudwatch", "list-metrics", "--namespace", spec["namespace"]]
    for k, v in dims.items():
        args += ["--dimensions", f"Name={k},Value={v}"]
    found = aws(*args).get("Metrics", [])
    return [m for m in found if m["MetricName"] in spec["metrics"]]


def get_data(queries, start, end):
    """queries is a list of (id, metric, stat). Returns {id: [(timestamp, value)]}."""
    result = {}
    for i in range(0, len(queries), BATCH):
        chunk = queries[i:i + BATCH]
        body = {"MetricDataQueries": [
            {"Id": qid, "MetricStat": {"Metric": metric, "Period": PERIOD, "Stat": stat}, "ReturnData": True}
            for qid, metric, stat in chunk
        ]}
        with tempfile.NamedTemporaryFile("w", suffix=".json", delete=False) as f:
            json.dump(body, f)
        try:
            data = aws("cloudwatch", "get-metric-data", "--cli-input-json", "file://" + f.name.replace("\\", "/"),
                       "--start-time", start, "--end-time", end)
        finally:
            os.unlink(f.name)
        for r in data.get("MetricDataResults", []):
            result.setdefault(r["Id"], []).extend(zip(r["Timestamps"], r["Values"]))
    return result


def main():
    p = argparse.ArgumentParser()
    p.add_argument("arm")
    p.add_argument("run_id")
    p.add_argument("--start", required=True, help="UTC, like 2026-10-01T10:00:00Z")
    p.add_argument("--end", required=True)
    p.add_argument("--backend", help="backend EC2 instance id")
    p.add_argument("--loadgen", help="load generator instance id")
    p.add_argument("--db", help="RDS instance identifier, the first part of the endpoint")
    p.add_argument("--out", help="output folder, default <arm>/results/<run-id>")
    a = p.parse_args()

    values = {k: v for k, v in {"backend": a.backend, "loadgen": a.loadgen, "db": a.db}.items() if v}
    specs = load(os.path.join(ROOT, "common", "queries.json")) + load(os.path.join(ROOT, a.arm, "queries.json"))

    queries, meta = [], {}
    for spec in specs:
        try:
            found = discover(spec, values)
        except KeyError as e:
            print(f"skipping {spec['source']} {spec['namespace']}: no --{e.args[0]} given")
            continue
        for m in found:
            dims = ";".join(f"{d['Name']}={d['Value']}" for d in m["Dimensions"] if d["Name"] not in spec["dimensions"])
            for stat in STATS:
                qid = f"q{len(queries)}"
                queries.append((qid, m, stat))
                meta[qid] = (spec["source"], spec["namespace"], m["MetricName"], dims, stat.lower())
        print(f"{spec['source']} {spec['namespace']}: {len(found)} metrics")

    data = get_data(queries, a.start, a.end)

    out = a.out or os.path.join(ROOT, a.arm, "results", a.run_id)
    os.makedirs(out, exist_ok=True)
    rows = 0
    with open(os.path.join(out, "metrics.csv"), "w", newline="") as f:
        w = csv.writer(f)
        w.writerow(["timestamp", "source", "namespace", "metric", "dims", "stat", "value"])
        for qid, points in data.items():
            for ts, v in sorted(points):
                w.writerow([ts, *meta[qid][:5], v])
                rows += 1
    with open(os.path.join(out, "run.json"), "w") as f:
        json.dump({"arm": a.arm, "run_id": a.run_id, "start": a.start, "end": a.end, **values, "rows": rows}, f, indent=2)
    print(f"wrote {rows} rows to {out}")


if __name__ == "__main__":
    sys.exit(main())
