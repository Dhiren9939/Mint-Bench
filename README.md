# Mint-Bench

Load tests for [Mint](https://github.com/Dhiren9939/Mint). Every benchmark arm uses the same harness so it lives here and not in the main repo.

## Arms

- `bench-sql`: the `db-sql` branch, RDS Postgres
- Dynamo without the cache
- Dynamo with the cache
- ECS, what `main` runs

Only the API and the database run in each arm, no S3 and no CloudFront. Every arm gets its own folder here for the seed data and the results.

## Layout

```text
Mint-Bench/
  loadgen/      terraform for the box k6 runs on
  k6/           the k6 script and the file list loader
  bench-sql/    seed script, data/ and results/
```

## Load generator

Debian 12 on a c6i.xlarge in the default VPC. `user_data.sh` installs k6, Redis (k6 keeps the file list in it) and the CloudWatch agent.

```bash
cd loadgen
terraform init
terraform plan -out plan
terraform apply plan
```

SSH in with `mintkey.pem` as `admin`. `ssh_cidr` defaults to `0.0.0.0/0`, pass your own IP if you want.

It isn't in the backend's VPC so it hits the backend over the public IP, through `mint-bench-sql.dhiren.xyz`. There's no Elastic IP so the record changes if the EC2 gets stopped and started.

## The users

Every VU loops forever. If the file list has files it uploads 2.6% of the time and downloads the rest. If the list is empty it uploads.

- Upload: POST the upload link, sleep 1 to 3 seconds for the S3 upload, PATCH to confirm, add the file to the list with 15 to 60 downloads.
- Download: pick a random file from the list and GET it.

A file leaves the list as soon as it runs out of downloads. An expired file stays for 2 more minutes so people keep hitting expired files. Those 404s are expected and don't count as errors.

Load goes 50, 100, 200, 400 VUs, 3 minutes each. Set `STAGES` to change it.

Thresholds are p95 under 200ms, p99 under 600ms, server errors under 1% and checks over 99%.

The numbers come from k6 only. Micrometer and CloudWatch are just kept in case I want to look deeper later. Still check the load generator CPU after a run, if it was maxed out the latency numbers are its fault.

## Running an arm

1. Raise all the `mint.cap.*` limits on the backend. Every VU shares one IP.
2. On the backend EC2 run the seed, RDS isn't reachable from anywhere else.
   ```bash
   PGHOST=<rds endpoint> PGUSER=... PGPASSWORD=... PGDATABASE=mintdb ./seed-rds.sh 10000
   ```
   It truncates `file_meta_data`, adds 10000 files split evenly between 15 min, 30 min and 24 hr expiry, and writes `seed.csv`. Do this right before the run since the expiry starts counting at seed time.
3. Copy `seed.csv` to the load generator and keep a copy in `bench-sql/data/`.
4. On the load generator: `./load-file-list.sh seed.csv`
5. Run k6.
   ```bash
   K6_BINARY_PROVISIONING=true k6 run \
     -e BASE_URL=http://mint-bench-sql.dhiren.xyz \
     --out csv=results.csv --summary-export=summary.json k6/mint.js
   ```
6. Copy the results into `bench-sql/results/` before tearing anything down.

## Notes

- k6 2.x removed `k6/experimental/redis`. The script uses `k6/x/redis` so it needs `K6_BINARY_PROVISIONING=true` to build the extension. Only tried it in Docker so far.
- 10000 seeded files are about 2.5 MB on the RDS disk.
- A GET on an expired file returns 404 and marks the row deleted, so it writes.
- The backend cleanup job runs every hour. The S3 delete fails with no bucket, it just gets logged.

## Todo

- Port the metrics to the arm's branch
- EC2 setup script (docker, CloudWatch agent, schema, build the image)
- Script to export the CloudWatch data
- The expired file path in the k6 script isn't tested and `user_data.sh` hasn't run on a real box yet
