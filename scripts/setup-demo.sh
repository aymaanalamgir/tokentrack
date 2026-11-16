#!/bin/sh
# TokenTrack: load the fictional demo (Alset, Northline Financial, Memento AI; 12 months from 2025-11-01) into a
# running Docker Compose stack: migrate, seed, generate the workload, fund, import, price, deliver, import agent
# executions, add controls and requests, apply one documented correction, then reconcile.
#
#   ./scripts/setup-demo.sh [--profile demo|smoke] [--seed 42]
#   DOCKER_COMPOSE="docker compose -p other" ./scripts/setup-demo.sh
#
# Every step is idempotent: imports replay as duplicates, funding/transfers/controls/requests use stable keys,
# and memberships are never rewritten. It never resets or deletes data. A conflict (for example, funding the
# same months with a different profile) stops with the step's output instead of being repaired.
# Exit codes: 0 ready; 1 a step failed; 64 bad arguments; 69 a service is unavailable.
set -eu
cd "$(dirname "$0")/.."
COMPOSE="${DOCKER_COMPOSE:-docker compose}"
PROFILE=demo SEED=42
while [ $# -gt 0 ]; do
  case "$1" in
    --profile) PROFILE="$2"; shift 2 ;;
    --seed) SEED="$2"; shift 2 ;;
    *) echo "Usage: $0 [--profile demo|smoke] [--seed N]" >&2; exit 64 ;;
  esac
done
COMPANIES="alset northline-financial memento-ai"
LOG_DIR="$(mktemp -d "${TMPDIR:-/tmp}/tokentrack-setup.XXXXXX")"
DIR="demo/enterprise/generated/${PROFILE}-seed${SEED}"
STEP=0
say() { printf '%s\n' "$*"; }
run() {
  title="$1"; allowed="$2"; shift 2
  STEP=$((STEP + 1)); log="$LOG_DIR/$(printf '%02d' "$STEP").log"
  printf '[%2d] %s ... ' "$STEP" "$title"
  t0=$(date +%s); set +e; "$@" >"$log" 2>&1; code=$?; set -e
  case " $allowed " in
    *" $code "*) say "ok ($(( $(date +%s) - t0 ))s)" ;;
    *) say "exit $code"; say "--- $log ---"; tail -n 30 "$log"; exit 1 ;;
  esac
  LAST_LOG="$log"
}
rails() { $COMPOSE exec -T core-api "$@"; }
usage() { $COMPOSE exec -T usage-engine bin/usage "$@"; }
source_for() { echo "enterprise-${1%%-*}-v1"; }

for service in postgres core-api usage-engine; do
  $COMPOSE ps --status running --services 2>/dev/null | grep -qx "$service" || { say "service '$service' is not running; start the stack with: docker compose up --build -d"; exit 69; }
done
# Wait for real readiness, not just a started container.
ready() { i=0; until "$@" >/dev/null 2>&1; do i=$((i + 1)); [ "$i" -ge 60 ] && return 1; sleep 3; done; }
ready $COMPOSE exec -T postgres sh -c 'pg_isready -h 127.0.0.1 -U "$POSTGRES_USER" -d "$POSTGRES_DB"' || { say "PostgreSQL is not accepting connections"; exit 69; }
ready $COMPOSE exec -T core-api ruby -rnet/http -e 'exit(Net::HTTP.get_response(URI("http://127.0.0.1:3001/api/v1/health")).code == "200" ? 0 : 1)' || { say "Rails health check did not pass"; exit 69; }

say "TokenTrack demo setup ($PROFILE, seed $SEED; logs: $LOG_DIR)"
run "Apply Rails migrations (development)" "0" rails bin/rails db:migrate
run "Apply Rails migrations (test database)" "0" rails env RAILS_ENV=test bin/rails db:migrate
# Seeds the companies first: events reference Rails-owned people and dated project memberships.
run "Seed companies and generate the workload" "0" ./scripts/generate-enterprise-demo.sh --profile "$PROFILE" --seed "$SEED"
run "Load pricing catalogue" "0" usage load-prices
run "Load synthetic historical pricing" "0" usage load-prices --file /app/demo/enterprise/pricing-historical-v1.json
run "Fund monthly accounts ($PROFILE)" "0" rails env PROFILE="$PROFILE" bin/rails enterprise_demo:fund
# One CLI start per company (JVM and Spring start-up dominate small steps); each monthly file is its own batch.
files() { for file in "$DIR/$1"/$2; do printf '/app/%s ' "$file"; done; }
for company in $COMPANIES; do
  # shellcheck disable=SC2046
  run "Import 12 months of usage ($company)" "0" usage import $(files "$company" 'usage-*.csv') --source "$(source_for "$company")"
done
for company in $COMPANIES; do
  # Exit 2: the demo deliberately includes a self-hosted model with no pricing profile.
  run "Price $(source_for "$company")" "0 2" usage price --source "$(source_for "$company")"
done
# Exit 2 means some deliveries were scheduled for retry (for example a transient FINANCIAL_SERVICE_UNAVAILABLE
# under load) - the outbox's designed path. Loop on the outbox's own counts until nothing is pending, retrying or
# leased; wait when only not-yet-due retries remain. Dead letters stop the run for inspection.
outbox_count() { sed -n '/"states"/,/]/p' "$LAST_LOG" | awk -v want="$1" '/"status"/{s=$3} /"count"/{n=$3; gsub(/[^0-9]/,"",n); if (s ~ want) t+=n} END{print t+0}'; }
remaining=1; round=0
while [ "$remaining" != "0" ]; do
  round=$((round + 1)); [ "$round" -le 40 ] || { say "delivery did not drain after 40 rounds"; exit 1; }
  run "Deliver priced usage (round $round)" "0 2" usage deliver --limit 10000 --workers 8
  [ "$(outbox_count dead)" = "0" ] || { say "FAILED: $(outbox_count dead) dead deliveries; inspect with: bin/usage delivery-report"; exit 1; }
  remaining=$(outbox_count 'pending|retry|delivering')
  attempted=$(grep -m1 '"attempted"' "$LAST_LOG" | tr -dc '0-9')
  [ "$remaining" = "0" ] || [ "${attempted:-0}" != "0" ] || { say "  waiting 30s for $remaining scheduled retries"; sleep 30; }
done
for company in $COMPANIES; do
  # shellcheck disable=SC2046
  run "Import 12 months of agent executions ($company)" "0" usage agent-import $(files "$company" 'executions-*.jsonl') --source "$(source_for "$company")"
done
run "Create controls, delegation and requests" "0" rails bin/rails enterprise_demo:controls
run "Apply the documented agent-cost correction" "0" rails bin/rails agents:demo_correction
# 0 = reconciled, 2 = balanced with unpriced usage or pending work, 3 = discrepancy.
run "Reconcile usage, pricing, delivery and ledger" "0 2" usage reconcile
grep -E '"(status|priced_events|posted_events|unpriced_events|pending_delivery|dead_deliveries|unresolved_charge_owner|amount_discrepancies|duplicate_expenses|unbalanced_transfers|net_expenditure_usd)"' "$LAST_LOG" | sed 's/^ */  /'
for key in pending_delivery dead_deliveries unresolved_charge_owner delivered_missing_postings amount_discrepancies duplicate_expenses unbalanced_transfers; do
  value=$(grep -m1 "\"$key\"" "$LAST_LOG" | tr -dc '0-9')
  [ "$value" = "0" ] || { say "FAILED: reconciliation reports $key=$value"; exit 1; }
done
run "Summary" "0" rails bin/rails enterprise_demo:summary
say ""
say "Demo ready. Open http://localhost:3000 and choose an identity, for example:"
say "  Alset: Nole Perfume (CEO) · Northline Financial: Amara Lindqvist (CEO), Hana Takeda (engineer) · Memento AI: Noor Haddad (CEO)"
say "Data covers 2025-11-01 to 2026-11-01 (UTC)."
