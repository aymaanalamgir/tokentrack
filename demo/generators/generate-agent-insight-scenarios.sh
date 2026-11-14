#!/bin/sh
# Slice 9B: deterministic agent-efficiency scenarios for the separate source demo-agent-insights-v1.
set -eu
cd "$(dirname "$0")/../.."
seed="${1:-42}"
exec docker compose exec -T usage-engine bin/usage generate-agent-insight-scenarios \
  --snapshot /app/demo/fixtures/organization-snapshot-v1.json \
  --usage-output /app/demo/fixtures/agent-insights-usage-v1.csv \
  --executions-output /app/demo/fixtures/agent-insights-executions-v1.jsonl \
  --seed "$seed"
