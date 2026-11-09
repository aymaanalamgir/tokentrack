#!/bin/sh
set -eu
if [ "$#" -lt 2 ] || [ "$#" -gt 3 ]; then
  printf '%s\n' 'Usage: demo/generators/generate-usage.sh FROM_DATE TO_DATE [SEED]' >&2
  exit 64
fi
cd "$(dirname "$0")/../.."
docker compose exec -T usage-engine bin/usage snapshot --output /app/demo/fixtures/organization-snapshot-v1.json
exec docker compose exec -T usage-engine bin/usage generate \
  --snapshot /app/demo/fixtures/organization-snapshot-v1.json \
  --output /app/demo/fixtures/usage-events-v1.csv \
  --invalid-output /app/demo/fixtures/usage-events-invalid-v1.csv \
  --seed "${3:-42}" --from "$1" --to "$2"
