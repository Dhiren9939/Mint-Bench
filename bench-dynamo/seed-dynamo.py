#!/usr/bin/env python3
"""Clean and seed the file metadata table, and write the matching file list to seed.csv.
Run on the backend EC2 (reseed.sh does it over ssh), the instance role has the rights:

  DYNAMO_TABLE=<table> AWS_REGION=ap-south-1 SEED_CSV=seed.csv python3 seed-dynamo.py [count]

Items are READY with a 15 min / 30 min / 24 h expiry (an equal third each) counted from now,
so seed right before the run. cleanAt is epoch seconds, same as the app writes it.
seed.csv columns: file_code,downloads_left(15..60),expires_at_epoch_ms
"""
import os
import random
import secrets
import sys
import time

import boto3

table = boto3.resource("dynamodb", region_name=os.environ.get("AWS_REGION", "ap-south-1")).Table(os.environ["DYNAMO_TABLE"])
count = int(sys.argv[1]) if len(sys.argv) > 1 else 10000
out = os.environ.get("SEED_CSV", "seed.csv")

# clean. There's no truncate in Dynamo, so scan the keys and delete them. This takes the items k6 uploaded too.
deleted = 0
with table.batch_writer() as batch:
    kwargs = {"ProjectionExpression": "fileCode", "ConsistentRead": True}
    while True:
        page = table.scan(**kwargs)
        for item in page["Items"]:
            batch.delete_item(Key={"fileCode": item["fileCode"]})
            deleted += 1
        if "LastEvaluatedKey" not in page:
            break
        kwargs["ExclusiveStartKey"] = page["LastEvaluatedKey"]
print(f"deleted {deleted} items")

codes = set()
while len(codes) < count:
    codes.add(secrets.token_hex(3))

durations = [("MINUTES15", 15 * 60), ("MINUTES30", 30 * 60), ("HOURS24", 24 * 3600)]
now = int(time.time())
rows = []
with table.batch_writer() as batch:
    for code in codes:
        dur, secs = random.choice(durations)
        clean_at = now + secs
        batch.put_item(Item={
            "fileCode": code,
            "fileKey": f"{secrets.token_hex(16)}.bin",
            "cleanAt": clean_at,
            "fileState": "READY",
            "fileExpiryDuration": dur,
        })
        rows.append((code, random.randint(15, 60), clean_at * 1000, dur))

with open(out, "w") as f:
    for code, left, expires_ms, _ in rows:
        f.write(f"{code},{left},{expires_ms}\n")

print(f"wrote {out} ({len(rows)} files)")
for dur, _ in durations:
    print(f"  {dur}: {sum(1 for r in rows if r[3] == dur)}")
