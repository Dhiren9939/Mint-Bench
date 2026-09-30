#!/usr/bin/env bash
# Clean and seed file_meta_data, and write the matching file list to seed.csv.
# Run on the backend EC2 (RDS is only reachable from there):
#   PGHOST=<rds endpoint> PGUSER=... PGPASSWORD=... PGDATABASE=mintdb ./seed-rds.sh [count]
#
# Rows are READY with a 15 min / 30 min / 24 h expiry (an equal third each) counted from now,
# so seed right before the run. clean_at is written in UTC, which assumes the backend JVM runs in UTC.
# seed.csv columns: file_code,downloads_left(15..60),expires_at_epoch_ms
set -euo pipefail

COUNT="${1:-10000}"
OUT="${SEED_CSV:-seed.csv}"

psql -v ON_ERROR_STOP=1 -v count="$COUNT" -v out="$OUT" <<'SQL'
TRUNCATE file_meta_data RESTART IDENTITY;

CREATE TEMP TABLE seed AS
WITH codes AS (
  SELECT DISTINCT substr(md5(random()::text || g::text), 1, 6) AS code
  FROM generate_series(1, :count * 2) g
)
SELECT code,
       (ARRAY['MINUTES15', 'MINUTES30', 'HOURS24'])[1 + floor(random() * 3)::int] AS dur,
       15 + floor(random() * 46)::int AS downloads_left
FROM codes
LIMIT :count;

ALTER TABLE seed ADD COLUMN clean_at timestamp;
UPDATE seed SET clean_at = (now() AT TIME ZONE 'UTC') + CASE dur
  WHEN 'MINUTES15' THEN interval '15 minutes'
  WHEN 'MINUTES30' THEN interval '30 minutes'
  ELSE interval '24 hours' END;

INSERT INTO file_meta_data (file_code, file_key, clean_at, file_state, file_expiry_duration)
SELECT code, gen_random_uuid()::text || '.bin', clean_at, 'READY', dur FROM seed;

COPY (SELECT code, downloads_left, (extract(epoch FROM clean_at) * 1000)::bigint FROM seed) TO STDOUT CSV \g :out

VACUUM ANALYZE file_meta_data;

SELECT dur AS expiry, count(*) FROM seed GROUP BY dur ORDER BY dur;
SELECT count(*) AS rows,
       pg_size_pretty(pg_table_size('file_meta_data')) AS table,
       pg_size_pretty(pg_indexes_size('file_meta_data')) AS indexes,
       pg_size_pretty(pg_total_relation_size('file_meta_data')) AS total
FROM file_meta_data;
SQL

echo "wrote $OUT ($(wc -l < "$OUT") files). Copy it to the load generator and run load-file-list.sh."
