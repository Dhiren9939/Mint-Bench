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
  common/       CloudWatch agent config, the metric lists and the export script, same for every arm
  loadgen/      terraform for the box k6 runs on
  k6/           the k6 script and the file list loader
  bench-sql/    setup script, seed script, data/ and results/
```

## Data

Every arm produces the same files in `<arm>/results/<run-id>/` so one analysis works on all of them.

- `k6.csv` and `summary.json` from k6
- `metrics.csv` from `common/export-run.py`, with the columns `timestamp,source,namespace,metric,dims,stat,value`. `source` is `backend`, `loadgen` or `db`.
- `run.json`, written by the export script

The backend gets the same CloudWatch agent config on every EC2 arm (`common/cwagent.json`): CPU including steal, memory, swap, disk, disk IO, network, and CPU and memory per process for java, redis-server, dockerd, containerd and the agent itself. `common/queries.json` lists what gets exported for the backend and the load generator, and each arm has a `queries.json` for its database (RDS for `bench-sql`).

```bash
python common/export-run.py bench-sql 2026-10-01-a \
  --start 2026-10-01T10:00:00Z --end 2026-10-01T11:00:00Z \
  --backend i-... --loadgen i-... --db <rds identifier>
```

Needs the aws CLI logged in. Export soon after a run, CloudWatch only keeps 1 minute data for 15 days.

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

A pass is k6 running N users: 5 minutes ramping up (warm up), 5 minutes holding N (the bench), 1 minute ramping down. Only the bench part counts for the thresholds. `WARMUP_S`, `BENCH_S` and `COOLDOWN_S` change the times.

A pass has to keep the thresholds: p95 under 200ms, p99 under 600ms, server errors under 1% and checks over 99%.

The numbers come from k6 only. Micrometer and CloudWatch are just kept in case I want to look deeper later. Still check the load generator CPU after a run, if it was maxed out the latency numbers are its fault.

## Running an arm

1. The backend EC2 sets itself up. The Mint infra runs `bench-sql/setup-ec2.sh` from user data: it clones Mint (`bench-sql` branch) and this repo into `/opt/src`, adds swap, installs docker and the CloudWatch agent, applies the schema, builds the image on the box and starts it with the `mint.cap.*` limits raised (every VU shares one IP). Both repos have to be public for the clone. It takes a few minutes after `terraform apply`. Watch it with `tail -f /var/log/user-data.log` over ssh, `/var/log/mint-ready` shows up when it's done. To retry by hand:
   ```bash
   sudo env MINT_DIR=/opt/src/Mint BENCH_DIR=/opt/src/Mint-Bench DB_HOST=<rds address> DB_USERNAME=... DB_PASSWORD=... bash /opt/src/Mint-Bench/bench-sql/setup-ec2.sh
   ```
2. Find the most users the arm holds. Connect to the load generator with `ssh -A` so it can reach the backend with your key (nothing gets stored on the box), then:
   ```bash
   git clone https://github.com/Dhiren9939/Mint-Bench.git && cd Mint-Bench
   export BACKEND=admin@<backend ip> DB_HOST=<rds address> DB_USERNAME=... DB_PASSWORD=...
   RESEED=bench-sql/reseed.sh k6/find-max.sh bench-sql
   ```
   It starts at 80 users. A pass doubles the users, a fail tries halfway between the last pass and the fail. It stops when they're 5 users apart. `START`, `TOL`, `MAX_VUS`, `REST_S` (rest between passes, 2 min) and `RUN_ID` are env vars.

   Before every pass `bench-sql/reseed.sh` cleans RDS, seeds 10000 files split evenly between 15 min, 30 min and 24 hr expiry, and loads the file list. RDS is only reachable from the backend so the seed runs there over ssh. The seeded expiry counts from seed time so every pass starts fresh.
3. Each pass leaves `bench-sql/results/<run-id>/vus-<N>/` with `k6.csv`, `summary.json`, `seed.csv` and `pass.json` (result and the bench start and end times). `search.json` in the run folder has the answer. Run the export script for the whole run before tearing anything down, from the first pass start to the last pass end.

## Notes

- k6 2.x removed `k6/experimental/redis`. The script uses `k6/x/redis` so it needs `K6_BINARY_PROVISIONING=true` to build the extension. Only tried it in Docker so far.
- 10000 seeded files are about 2.5 MB on the RDS disk.
- A GET on an expired file returns 404 and marks the row deleted, so it writes.
- The backend cleanup job runs every hour. The S3 delete fails with no bucket, it just gets logged.

## Todo

- `setup-ec2.sh` and the export script haven't run against real AWS yet. The dimensions the agent puts on its metrics might need a tweak in `queries.json`.
- The expired file path in the k6 script isn't tested and `user_data.sh` hasn't run on a real box yet
