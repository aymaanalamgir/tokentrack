#!/bin/sh
# Generate the twelve-month enterprise demo workload (Alset, Northline Financial, Memento AI).
#
#   ./scripts/generate-enterprise-demo.sh [--profile demo|smoke] [--seed 42] [--start 2025-11-01] [--company alset,...]
#
# Seeds the fictional companies in Rails (idempotent; required because events reference Rails-owned people and
# dated project memberships), exports their organizational snapshot, then writes per-month usage CSV and agent
# execution JSONL to demo/enterprise/generated/<profile>-seed<seed>/. Same spec + snapshot + seed + profile
# gives byte-identical files (hashes in manifest.json). It does not import, price or post anything.
set -eu
cd "$(dirname "$0")/.."
COMPOSE="${DOCKER_COMPOSE:-docker compose}"
PROFILE=demo SEED=42 START="" COMPANY=""
while [ $# -gt 0 ]; do
  case "$1" in
    --profile) PROFILE="$2"; shift 2 ;;
    --seed) SEED="$2"; shift 2 ;;
    --start) START="$2"; shift 2 ;;
    --company) COMPANY="$2"; shift 2 ;;
    *) echo "Usage: $0 [--profile demo|smoke] [--seed N] [--start YYYY-MM-DD] [--company slug,...]" >&2; exit 64 ;;
  esac
done
case "$PROFILE" in demo|smoke) ;; *) echo "profile must be demo or smoke" >&2; exit 64 ;; esac
case "$SEED" in ''|*[!0-9]*) echo "seed must be a non-negative integer" >&2; exit 64 ;; esac
ORGS=alset,northline-financial,memento-ai
OUT="/app/demo/enterprise/generated/${PROFILE}-seed${SEED}"
$COMPOSE exec -T core-api bin/rails db:migrate >/dev/null
$COMPOSE exec -T ${COMPANY:+-e COMPANY="$COMPANY"} core-api bin/rails enterprise_demo:seed >/dev/null
$COMPOSE exec -T usage-engine bin/usage snapshot --organizations "$ORGS" --output "$OUT/snapshot.json" >/dev/null
start=$(date +%s)
$COMPOSE exec -T usage-engine bin/usage generate-enterprise-demo --spec /app/demo/enterprise/companies-v1.json --snapshot "$OUT/snapshot.json" \
  --output-dir "$OUT" --seed "$SEED" --profile "$PROFILE" ${START:+--start "$START"} ${COMPANY:+--company "$COMPANY"}
echo "Generated in $(( $(date +%s) - start ))s: demo/enterprise/generated/${PROFILE}-seed${SEED}/"
