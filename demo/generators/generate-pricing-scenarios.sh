#!/bin/sh
set -eu
cd "$(dirname "$0")/../.."
exec docker compose exec -T usage-engine bin/usage generate-pricing-scenarios \
  --snapshot /app/demo/fixtures/organization-snapshot-v1.json \
  --output /app/demo/fixtures/pricing-scenarios-v1.csv
