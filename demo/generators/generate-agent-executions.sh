#!/usr/bin/env bash
set -euo pipefail
seed="${1:-42}"
source_name="${2:-demo-synthetic-v1}"
docker compose exec usage-engine bin/usage generate-agent-executions --output /app/demo/fixtures/agent-executions-v1.jsonl --invalid-output /app/demo/fixtures/agent-executions-invalid-v1.jsonl --seed "$seed" --source "$source_name"
