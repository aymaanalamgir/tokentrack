#!/bin/sh
# Load the enterprise demo companies into a running stack: seed, generate, fund, import, price, deliver,
# import agent executions, add controls and requests, then reconcile.
#
#   ./scripts/setup-enterprise-demo.sh [--profile demo|smoke] [--seed 42]
#
# Every step is idempotent: imports replay as duplicates, funding/transfers/controls/requests use stable keys,
# and memberships are never rewritten. The existing demo companies are untouched. A conflict (for example,
# funding the same months with a different profile) stops with the step's output rather than being repaired.
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
LOG_DIR="$(mktemp -d "${TMPDIR:-/tmp}/tokentrack-enterprise.XXXXXX")"
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
for service in postgres core-api usage-engine; do
  $COMPOSE ps --status running --services 2>/dev/null | grep -qx "$service" || { say "service '$service' is not running"; exit 69; }
done
say "TokenTrack enterprise demo ($PROFILE, seed $SEED; logs: $LOG_DIR)"
run "Generate workload (seeds companies)" "0" ./scripts/generate-enterprise-demo.sh --profile "$PROFILE" --seed "$SEED"
run "Load synthetic historical pricing" "0" usage load-prices --file /app/demo/enterprise/pricing-historical-v1.json
run "Fund monthly accounts ($PROFILE)" "0" rails env PROFILE="$PROFILE" bin/rails enterprise_demo:fund
for company in alset northline-financial memento-ai; do
  for file in "$DIR/$company"/usage-*.csv; do
    run "Import $(basename "$file") ($company)" "0" usage import "/app/$file" --source "enterprise-${company%%-*}-v1"
  done
done
for source in enterprise-alset-v1 enterprise-northline-v1 enterprise-memento-v1; do
  # Exit 2: the demo deliberately includes a self-hosted model with no pricing profile.
  run "Price $source" "0 2" usage price --source "$source"
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
for company in alset northline-financial memento-ai; do
  for file in "$DIR/$company"/executions-*.jsonl; do
    run "Import $(basename "$file") ($company)" "0" usage agent-import "/app/$file" --source "enterprise-${company%%-*}-v1"
  done
done
run "Create controls, delegation and requests" "0" rails bin/rails enterprise_demo:controls
run "Reconcile" "0 2" usage reconcile
grep -E '"(status|priced_events|posted_events|unpriced_events|pending_delivery|dead_deliveries|unresolved_charge_owner|amount_discrepancies|duplicate_expenses|unbalanced_transfers|net_expenditure_usd)"' "$LAST_LOG" | sed 's/^ */  /'
for key in pending_delivery dead_deliveries unresolved_charge_owner delivered_missing_postings amount_discrepancies duplicate_expenses unbalanced_transfers; do
  value=$(grep -m1 "\"$key\"" "$LAST_LOG" | tr -dc '0-9')
  [ "$value" = "0" ] || { say "FAILED: reconciliation reports $key=$value"; exit 1; }
done
run "Summary" "0" rails bin/rails enterprise_demo:summary
say "Enterprise demo ready. Identities: Nole Perfume (Alset), Amara Lindqvist (Northline Financial), Noor Haddad (Memento AI)."
