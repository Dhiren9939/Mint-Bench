# Mint-Bench

Load tests for [Mint](https://github.com/Dhiren9939/Mint). Every benchmark arm uses the same harness so it lives here and not in the main repo.

## Arms

- `bench-sql`: the `db-sql` branch, RDS Postgres
- `bench-dynamo`: Dynamo without the cache, the `bench-dynamo-lua` branch
- Dynamo with the cache
- ECS, what `main` runs

Only the API and the database run in each arm, no S3 and no CloudFront. Every arm gets its own folder here for the results.

## Layout

```text
Mint-Bench/
  common/       CloudWatch agent config, metric lists, export and summary scripts, same for every arm
  loadgen/      terraform for the box k6 runs on
  k6/           the k6 script, the search script and the file list loader
  bench-sql/    setup, seed, start and after scripts, and results/
  bench-dynamo/ the same for the Dynamo arm
  dashboard/    the dashboard: build.py collects the results, app/ is the React page
  local/        the docker replica used to find the Bucket4j retry storm
```

## Results

- `bench-sql`: 1420 users pass, 1425 fail (run `2026-09-30-0953`). That's about 284 requests per second on a t3.micro with RDS.

## The users

Every VU loops forever, with a 5 second pause before it starts the loop again (`THINK_MS`). The pause is the same every time. Set `THINK_JITTER=0.5` to make it random between 2.5 and 7.5 seconds (same average) so the users don't stay in step. If the file list has files it uploads 2.6% of the time and downloads the rest. If the list is empty it uploads.

- Upload: POST the upload link, sleep 1 to 3 seconds for the S3 upload, PATCH to confirm, add the file to the list with 15 to 60 downloads.
- Download: pick a random file from the list and GET it.

A file leaves the list as soon as it runs out of downloads. An expired file stays for 2 more minutes so people keep hitting expired files. Those 404s are expected and don't count as errors.

A user makes about 0.2 requests per second, so 1000 users is about 200 requests per second.

## How a run works

A pass is k6 running N users: 2 minutes ramping up (warm up), 5 minutes holding N (the bench), 2 minutes ramping down. Only the bench part counts. It passes if p95 stays under 200ms, p99 under 600ms, server errors under 1% and checks over 99%. `WARMUP_S`, `BENCH_S` and `COOLDOWN_S` change the times.

`k6/find-max.sh` looks for the most users the arm holds. It starts at 30 users. A pass doubles the users, a fail tries halfway between the last pass and the fail. It stops when they're 5 users apart. `START`, `TOL`, `MAX_VUS`, `REST_S` (rest between passes) and `RUN_ID` are env vars. Before every pass the arm's reseed script cleans the database and loads the file list, so every pass starts fresh.

The numbers come from k6 only. CloudWatch is there to explain why a pass failed. Check the load generator CPU too, if it was maxed out the latency numbers are its fault.

## Running an arm

1. Backend. The Mint infra sets it up from user data by running `bench-sql/setup-ec2.sh`: it clones Mint (`bench-sql` branch) and this repo into `/opt/src`, adds swap, installs docker and the CloudWatch agent, applies the schema, builds the image on the box and starts it with the `mint.cap.*` limits raised (every VU shares one IP). Both repos have to be public. It takes a few minutes after `terraform apply`, watch it with `tail -f /var/log/user-data.log`, `/var/log/mint-ready` shows up when it's done.
2. Load generator. Debian 12 on a c6i.xlarge in the default VPC, `user_data.sh` installs k6, Redis (k6 keeps the file list in it) and the CloudWatch agent.
   ```bash
   cd loadgen
   terraform init
   terraform plan -out plan
   terraform apply plan
   ```
   Don't change `user_data.sh` once it's running, the box gets replaced. It isn't in the backend's VPC so it hits the backend over the public IP through `mint-bench-sql.dhiren.xyz`. No Elastic IP, so the address changes if it gets stopped and started.
3. On the load generator, clone this repo, copy your key onto the box and fill in the settings:
   ```bash
   git clone https://github.com/Dhiren9939/Mint-Bench.git && cd Mint-Bench
   cp bench-sql/bench.env.example bench-sql/bench.env    # then fill it in, it's gitignored
   ```
4. Run it, inside `tmux` since it takes an hour or more and stops if the ssh session drops:
   ```bash
   bench-sql/start.sh
   ```
   It checks the api, the ssh to the backend and Redis first. Progress prints in the terminal and a copy goes to `bench-sql/results/<run-id>/run.log`. `DETACH=1` runs it in the background. It's done when it prints the answer and `search.json` shows up.
5. When it's done, on the load generator: `bench-sql/after.sh`. It pulls the CloudWatch numbers for every attempt into `metrics.csv`. Wait a few minutes after the last attempt, CloudWatch is behind. It reads with the box's own role (`read_metrics` in `loadgen/main.tf`).
6. On your machine, copy everything down before tearing anything down:
   ```bash
   LOADGEN_IP=... SSH_KEY=<mintkey.pem> bench-sql/fetch.sh <run-id>
   ```

## Data

Every attempt leaves `<arm>/results/<run-id>/vus-<N>/`, the same files for every arm so one analysis works on all of them.

- `k6.csv.gz`, every raw k6 sample. Gitignored, it's too big for git.
- `summary.json`, k6's own summary
- `seed.csv`, the files that were seeded
- `pass.json`, pass or fail and the warm up, bench and end times
- `metrics.csv`, from `common/export-run.py`. Columns `timestamp,source,namespace,metric,dims,stat,value`, `source` is `backend`, `loadgen` or `db`.
- `run.json`, written by the export script

`search.json` in the run folder has the answer.

`python common/summarize.py <arm> <run-id>` makes tables from the raw data, whenever you want them: `stats.csv` (per phase and request name: count, rps, p50, p95, p99, avg, max, failed, 5xx) and `timeline.csv` (the same per 10 seconds, with the users) in every attempt, and `attempts.csv` in the run folder with the bench part of every attempt.

## Dashboard

One dashboard for every arm and every version, `dashboard.html` in the root. It is a React app (Vite, Chart.js) in `dashboard/app`, built with bun into one file that opens by double clicking it. The runs in it are listed in `dashboard/runs.json` (arm, run id and a label). For a new run, make its tables, add a line to `runs.json` and build again:

```bash
python common/summarize.py <arm> <run-id>
# add {"arm": "<arm>", "run": "<run-id>", "label": "<version name>"} to dashboard/runs.json
python dashboard/build.py                          # collects the data into dashboard/app/src/data.json
cd dashboard/app && bun install && bun run build   # writes dashboard.html in the root
```

While working on the page itself, `bun run dev` in `dashboard/app` serves it with hot reload (run `build.py` first, it needs `src/data.json`). `data.json`, `node_modules` and `dist` are gitignored, `dashboard.html` has the data in it.

One chart and a list of attempts. Pick a metric (latency, requests per second, CPU, memory, RDS ...) and whether users or time is on the x axis. By users draws a line per version with a point per attempt (filled is a pass, hollow is a fail), over time draws the attempts you picked in the list, up to 7, from any version. Drag on the chart to zoom into a band, sideways zooms x only and up and down zooms y only. Drag along an axis to change just that axis. Shift and drag moves the chart, scroll zooms, double click resets. Zooming in stops at 50 times and zooming out at the full view. The address holds the view (metric, axis, picked attempts), so a link or a bookmark opens the same thing. Notes shows `story.txt` from each run folder (first line is the heading, blank lines split paragraphs), the explanation of that version.

The backend gets the same CloudWatch agent config on every EC2 arm (`common/cwagent.json`): CPU including steal, memory, swap, disk, disk IO, network, and CPU and memory per process for java, redis-server, dockerd, containerd and the agent itself. `common/queries.json` lists what gets exported for the backend and the load generator, and each arm has a `queries.json` for its database.

## bench-dynamo

Same flow as `bench-sql` with `bench-dynamo/` in place of `bench-sql/`: `terraform apply` in the Mint `bench-dynamo-lua` branch gets the backend ready from user data (`bench-dynamo/setup-ec2.sh`), then on the load generator `bench-dynamo/start.sh` and `bench-dynamo/after.sh`, and `bench-dynamo/fetch.sh` on your machine. ssh into the backend is only for watching it with `htop`. The processing (`common/summarize.py`) runs on your machine on the fetched data, not on the load generator.

- Backend: the Mint `bench-dynamo-lua` branch, Lua rate limiter, file metadata cache off (`mint.cache.enabled=false`), Redis is a container next to the api. The API talks to DynamoDB with the box's instance role, there are no keys.
- Table: `mint-bench-dynamo-file-metadata`, on demand. `bench.env` takes it as `DYNAMO_TABLE`, `after.sh` uses it as the `--db` for the `AWS/DynamoDB` metrics in `bench-dynamo/queries.json`.
- Reseed: Dynamo has no truncate, so `seed-dynamo.py` scans and deletes every item and writes 10000 new ones. It runs on the backend over ssh (its role can write the table) and `reseed.sh` copies `seed.csv` back. Needs `python3-boto3`, `setup-ec2.sh` installs it.
- The api is at `mint-bench-dynamo.dhiren.xyz`.

## Notes

- k6 2.x removed `k6/experimental/redis`. The script uses `k6/x/redis` so it needs `K6_BINARY_PROVISIONING=true`, `find-max.sh` sets it.
- 10000 seeded files are about 2.5 MB on the RDS disk.
- A GET on an expired file returns 404 and marks the row deleted, so it writes.
- Redis on the backend is the rate limiter (Bucket4j), three calls per request. It uses about a fifth of the box.
- The backend cleanup job runs every hour. The S3 delete fails with no bucket, it just gets logged.

## Todo

- A pass is about 9 minutes and the shortest expiry is 15, so the expired file path in the k6 script never fires. Seed with random ages if I want it tested.
- Restart the api container before every pass so each one starts from the same state.
