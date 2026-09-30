#!/usr/bin/env bash
# Replace the shared file list in the local Redis with the rows from seed.csv (see seed-rds.sh).
# Run on the load generator right before k6:  ./load-file-list.sh seed.csv
set -euo pipefail

CSV="${1:?usage: load-file-list.sh seed.csv}"
GRACE_MS="${GRACE_MS:-120000}"

redis-cli DEL pool left exp gc > /dev/null

# columns: code, downloads_left, expires_at_ms. gc score = expiry + grace, matching mint.js.
awk -F, -v grace="$GRACE_MS" '{
  printf "SADD pool %s\nHSET left %s %s\nHSET exp %s %s\nZADD gc %.0f %s\n", $1, $1, $2, $1, $3, $3 + grace, $1
}' "$CSV" | redis-cli > /dev/null

echo "file list loaded: $(redis-cli SCARD pool) files"
