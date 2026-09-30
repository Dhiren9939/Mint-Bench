# Mint-Bench

Benchmark harness for [Mint](../Mint). It lives here, and not in the Mint repo, because it is shared by every
arm and `main` must never carry benchmark config. The Mint repo only holds each arm's own backend and infra.

## Arms

Every arm is backend-only: API + database on one EC2 (t3.micro, unlimited credits), no S3 bucket, no CloudFront.
Presigned URLs are generated locally, so no bucket has to exist.

| Arm | Mint branch | Database | Status |
|---|---|---|---|
| `bench-sql` | `bench-sql` (off `db-sql`) | RDS PostgreSQL | infra stripped, harness ready, not yet run |
| Dynamo, no cache | from `ccafea2` | DynamoDB, `mint.cache.enabled=false` | not started |
| Dynamo + cache | from `ccafea2` | DynamoDB + Redis cache | not started |
| ECS | `main` | prod shape | not started |

Each arm gets a folder here (`bench-sql/`, ...) holding its `data/` (seed files) and `results/` (k6 output).

## Layout

| Path | What |
|---|---|
| `loadgen/` | Terraform root for the load generator. **Shared by all arms**, separate state (`projects/mint-loadgen.tfstate`). |
| `k6/mint.js` | The k6 load test (one user loop). |
| `k6/load-file-list.sh` | Loads a seed file list into the load generator's Redis. |
| `<arm>/seed-rds.sh` | Cleans and seeds that arm's database and writes `seed.csv`. |
| `<arm>/data/`, `<arm>/results/` | Seed files and results for that arm. |

## Load generator (`loadgen/`)

- Default VPC, Debian 12, `c6i.xlarge` (4 vCPU, 8 GiB, no CPU credits). Change with `instance_type`.
- `user_data.sh` installs k6, a local Redis (loopback only), and the CloudWatch agent (`MintLoadgen` namespace:
  CPU, memory, network). It also raises file and port limits.
- SSH in with `mintkey.pem` as user `admin`. Port 22 is limited to `ssh_cidr`, which has no default: pass your IP.
- The backend is reached over the public internet, since the load generator is not in the backend's VPC.
  The backend's port 80 is open to the world, and Route53 points `mint-bench-sql.<domain>` at the EC2 public IP.
  There is no Elastic IP, so the IP (and record) changes if the instance is stopped and started.

```
cd loadgen
terraform init
terraform plan -var 'ssh_cidr=<your ip>/32' -out plan
terraform apply plan
```

`terraform apply -auto-approve` is blocked as a blind apply: always plan to a file first.

## The user model (`k6/mint.js`)

Every VU is a user running one loop, forever. Each iteration:

- If the file list is empty, upload. Otherwise upload with 2.6% probability (`UPLOAD_CHANCE`), else download.
- **Upload:** `POST /api/v1/file/upload` (expiry 15 min / 30 min / 24 h, an equal third each) -> sleep 1-3 s
  (stands in for the S3 PUT) -> `PATCH /api/v1/file` -> add the file to the list with a random download
  count in 15..60.
- **Download:** claim a random file from the list, `GET /api/v1/file/{code}`.

The shared file list is in the load generator's Redis (`pool`, `left`, `exp`, `gc`):

- The download that takes a file's count to 0 removes it immediately.
- An expired file stays listed for 2 minutes after expiry (users keep hitting it, expecting a 404), then is removed.
  Hits on expired files do not use up the download count. Hits within 2 s of expiry accept 200 or 404 (clock skew).
- There is no think time between iterations (`THINK_MS` adds one).

Load profile: `ramping-vus` (closed model), a warm-up then a stair-step of 50 / 100 / 200 / 400 VUs, 3 min per step.
Override with `STAGES` (a JSON array).

### Thresholds

p95 < 200 ms and p99 < 600 ms per endpoint (`upload`, `confirm`, `download`, `download_expired`),
`server_errors` < 1%, `http_req_failed` < 1%, `checks` > 99%. Summary stats are `med, p(95), p(99), avg, max`.

### Measurement scope

Conclusions come from the k6 data alone. Micrometer, the CloudWatch dashboard and the CloudWatch agent / RDS
metrics are kept only as a record for a possible deeper analysis. The one thing to check after every run is the
load generator's own CPU (`MintLoadgen` metrics): if it ran hot, the latency numbers are the generator's.

## Running an arm

Seed right before the run: `clean_at` is relative to seeding, so a 15-minute file expires 15 minutes later.

1. **Rate limits.** Raise every `mint.cap.*` on the backend (global, ip and user, get and post). All VUs share one
   IP, and the per-user (cookie) cap would trip on a long loop.
2. **Seed the database**, on the backend EC2 (RDS is only reachable from there):
   ```
   PGHOST=<rds endpoint> PGUSER=... PGPASSWORD=... PGDATABASE=mintdb ./seed-rds.sh 10000
   ```
   It truncates `file_meta_data`, inserts 10,000 READY rows (an equal third of 15 min / 30 min / 24 h), and writes
   `seed.csv` (`code,downloads_left,expires_at_epoch_ms`). `clean_at` is UTC, which assumes the backend JVM runs in UTC.
3. **Copy `seed.csv`** to the load generator (`bench-sql/data/` here keeps a copy).
4. **Load the file list**, on the load generator: `./load-file-list.sh seed.csv`.
5. **Run k6:**
   ```
   K6_BINARY_PROVISIONING=true k6 run \
     -e BASE_URL=http://mint-bench-sql.<domain> \
     --out csv=results.csv --summary-export=summary.json k6/mint.js
   ```
6. **Capture results** into `<arm>/results/` before tearing the arm down.

### k6 needs the Redis extension

k6 v2 removed `k6/experimental/redis`. The script uses `k6/x/redis`, an extension. `K6_BINARY_PROVISIONING=true`
makes k6 build a binary with it (needs outbound internet). Verified in Docker with k6 v2.3.0; not yet verified on
the load-generator box.

## Seed size on RDS

10,000 rows take **about 2.5 MB** (measured on PostgreSQL 16: 1,112 kB table + 1,472 kB indexes = 2,584 kB,
about 260 bytes per row). It is negligible against RDS's minimum storage. `seed-rds.sh` prints the real numbers.

## Verification so far

- `seed-rds.sh` ran against PostgreSQL 16 with the real `schema.sql`: 10,000 rows, mix roughly a third each.
- `mint.js` and both Redis Lua scripts ran in Docker (k6 v2.3.0, Redis 7) against a small mock of the three
  endpoints: 15,995 requests, 100% of checks passed.
- **Not yet exercised:** the expired-file path (`download_expired` got no hits: only 3 of 10,003 entries were expired),
  the load-generator `user_data.sh` on a real box, and anything against the real backend.

## Known behaviours of the backend to expect

- A `GET` on an expired file returns 404 and **writes** (it marks the row `DELETED`); later hits are read-only 404s.
- The backend's hourly cleanup job deletes rows expired for more than 2 minutes and calls S3 delete for each.
  With no bucket, those S3 calls fail (logged, the row is already deleted). This costs a little CPU on the box.
- Upload returns 201, confirm 200, download 200, missing or expired file 404.

## Pending

Port the metrics (`MetricsConfig`, Hikari `maximum-pool-size=10`, monitoring module) to the arm's branch, the EC2
setup script (docker, CloudWatch agent, `schema.sql`, build the image, compose up), and the results export script.
