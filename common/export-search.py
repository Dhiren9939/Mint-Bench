#!/usr/bin/env python3
"""Runs export-run.py for every attempt of a find-max run, so each attempt folder gets its own
metrics.csv (CloudWatch, EC2 and RDS) for its time window.

  python common/export-search.py <arm> <run-id> --backend i-... --loadgen i-... --db <rds identifier>

The window is the whole attempt (warm up, bench, cool down) plus 2 minutes either side.
pass.json has the bench start and end if you only want that part.
Needs the aws CLI logged in. CloudWatch is a couple of minutes behind, so wait a bit after the last attempt.
"""
import argparse
import glob
import json
import os
import subprocess
import sys
from datetime import datetime, timezone

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
MARGIN_S = 120


def iso(epoch):
    return datetime.fromtimestamp(epoch, timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("arm")
    ap.add_argument("run_id")
    ap.add_argument("--backend")
    ap.add_argument("--loadgen")
    ap.add_argument("--db")
    ap.add_argument("--cache")
    a = ap.parse_args()

    run = os.path.join(ROOT, a.arm, "results", a.run_id)
    for path in sorted(glob.glob(os.path.join(run, "vus-*", "pass.json"))):
        meta = json.load(open(path))
        cmd = [sys.executable, os.path.join(HERE, "export-run.py"), a.arm,
               f"{a.run_id}/vus-{meta['vus']}",
               "--start", iso(meta["start"] - MARGIN_S), "--end", iso(meta["end"] + MARGIN_S)]
        for flag in ("backend", "loadgen", "db", "cache"):
            if getattr(a, flag):
                cmd += [f"--{flag}", getattr(a, flag)]
        print("exporting", meta["vus"], "users")
        subprocess.run(cmd, check=True)


if __name__ == "__main__":
    main()
