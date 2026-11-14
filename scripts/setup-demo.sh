#!/bin/sh
# TokenTrack: load the complete fictional demo into a running Docker Compose stack.
#
# Orchestrates the existing, individually idempotent setup commands in dependency order. It never resets,
# deletes or regenerates data: imports replay as duplicates, ledger operations use stable request keys, and a
# conflict with existing records stops the run with the failing step's output instead of being repaired.
#
#   ./scripts/setup-demo.sh            # full setup
#   DOCKER_COMPOSE="docker compose -p other" ./scripts/setup-demo.sh
#
# Exit codes: 0 demo ready; 1 a step failed (its log is printed); 69 a required service is unavailable.
set -eu
cd "$(dirname "$0")/.."
COMPOSE="${DOCKER_COMPOSE:-docker compose}"
LOG_DIR="$(mktemp -d "${TMPDIR:-/tmp}/tokentrack-setup.XXXXXX")"
SOURCE_MAIN=demo-synthetic-v1
SOURCE_PRICING=demo-pricing-scenarios-v1
SOURCE_INSIGHTS=demo-agent-insights-v1
STEP=0
TOTAL=20

say() { printf '%s\n' "$*"; }
fail() { say "FAILED: $1"; [ -f "${2:-}" ] && { say "--- last output ($2) ---"; tail -n 40 "$2"; }; exit "${3:-1}"; }

# run "title" "allowed exit codes" command...   (stdout+stderr go to a per-step log)
run() {
  title="$1"; allowed="$2"; shift 2
  STEP=$((STEP + 1)); log="$LOG_DIR/$(printf '%02d' "$STEP").log"
  printf '[%2d/%d] %s ... ' "$STEP" "$TOTAL" "$title"
  set +e; "$@" >"$log" 2>&1; code=$?; set -e
  case " $allowed " in
    *" $code "*) say "ok$([ "$code" -ne 0 ] && printf ' (exit %s: see note)' "$code")" ;;
    *) say "exit $code"; fail "$title" "$log" 1 ;;
  esac
  LAST_LOG="$log"
}
rails() { $COMPOSE exec -T core-api "$@"; }
usage() { $COMPOSE exec -T usage-engine bin/usage "$@"; }
field() { grep -m1 "\"$1\"" "$2" | sed -E 's/.*: *"?([^",]*)"?,?$/\1/'; }

say "TokenTrack demo setup (logs: $LOG_DIR)"
for service in postgres core-api usage-engine; do
  $COMPOSE ps --status running --services 2>/dev/null | grep -qx "$service" || fail "service '$service' is not running; start the stack with: docker compose up --build -d" "" 69
done
# Wait for real readiness, not just a started container.
ready() { i=0; until "$@" >/dev/null 2>&1; do i=$((i + 1)); [ "$i" -ge 60 ] && return 1; sleep 3; done; }
ready $COMPOSE exec -T postgres sh -c 'pg_isready -h 127.0.0.1 -U "$POSTGRES_USER" -d "$POSTGRES_DB"' || fail "PostgreSQL is not accepting connections" "" 69
ready $COMPOSE exec -T core-api ruby -rnet/http -e 'exit(Net::HTTP.get_response(URI("http://127.0.0.1:3001/api/v1/health")).code == "200" ? 0 : 1)' || fail "Rails health check did not pass" "" 69

run "Apply Rails migrations (development)" "0" rails bin/rails db:migrate
run "Apply Rails migrations (test database)" "0" rails env RAILS_ENV=test bin/rails db:migrate
run "Seed fictional organizations" "0" rails bin/rails db:seed
run "Create demo accounts and synthetic funding (2026-11, 2026-12)" "0" rails env MONTHS=2026-11,2026-12 bin/rails finance:demo_setup
run "Grant demo budget read access" "0" rails bin/rails analytics:demo_access
# Kotlin applies its Flyway migrations when the CLI starts.
run "Load pricing catalogue" "0" usage load-prices
run "Load agent-scenario pricing mappings" "0" usage load-prices --file /app/demo/fixtures/agent-insights-pricing-v1.json
run "Import canonical usage ($SOURCE_MAIN)" "0" usage import /app/demo/fixtures/usage-events-v1.csv --source "$SOURCE_MAIN"
run "Import pricing scenarios ($SOURCE_PRICING)" "0" usage import /app/demo/fixtures/pricing-scenarios-v1.csv --source "$SOURCE_PRICING"
run "Import agent-scenario usage ($SOURCE_INSIGHTS)" "0" usage import /app/demo/fixtures/agent-insights-usage-v1.csv --source "$SOURCE_INSIGHTS"
# Exit 2 is expected: the demo deliberately contains usage without a supported pricing profile.
run "Price usage ($SOURCE_MAIN)" "0 2" usage price --source "$SOURCE_MAIN"
run "Price usage ($SOURCE_PRICING)" "0 2" usage price --source "$SOURCE_PRICING"
run "Price usage ($SOURCE_INSIGHTS)" "0 2" usage price --source "$SOURCE_INSIGHTS"
run "Deliver priced usage to the ledger" "0" usage deliver --limit 10000 --workers 4
run "Import agent executions ($SOURCE_MAIN)" "0" usage agent-import /app/demo/fixtures/agent-executions-v1.jsonl --source "$SOURCE_MAIN"
run "Import agent executions ($SOURCE_INSIGHTS)" "0" usage agent-import /app/demo/fixtures/agent-insights-executions-v1.jsonl --source "$SOURCE_INSIGHTS"
run "Create spending-control examples" "0" rails env SMALL_BUDGET_SCENARIO=true bin/rails budgets:demo_setup
run "Create request scenarios" "0" rails bin/rails requests:demo_setup
run "Apply the documented agent-cost correction" "0" rails bin/rails agents:demo_correction
# 0 = reconciled, 2 = balanced with unpriced usage or pending work, 3 = discrepancy.
run "Reconcile usage, pricing, delivery and ledger" "0 2" usage reconcile
RECONCILE="$LAST_LOG"

status="$(field status "$RECONCILE")"
say ""
say "Reconciliation: $status"
for key in priced_events posted_events unpriced_events pending_delivery dead_deliveries unresolved_charge_owner delivered_missing_postings amount_discrepancies duplicate_expenses unbalanced_transfers net_expenditure_usd; do
  printf '  %-28s %s\n' "$key" "$(field "$key" "$RECONCILE")"
done
for key in pending_delivery dead_deliveries unresolved_charge_owner delivered_missing_postings amount_discrepancies duplicate_expenses unbalanced_transfers; do
  [ "$(field "$key" "$RECONCILE")" = "0" ] || fail "reconciliation reports $key=$(field "$key" "$RECONCILE")" "$RECONCILE" 1
done
case "$status" in
  reconciled) ;;
  balanced_with_unpriced_usage) say "  Unpriced usage is intentional demo coverage; its cost is unknown, not zero." ;;
  *) fail "unexpected reconciliation status '$status'" "$RECONCILE" 1 ;;
esac
say ""
say "Demo ready. Open http://localhost:${FRONTEND_PORT:-3000} and choose Aperture Technologies -> Olivia Chen."
say "Walkthrough: docs/demo-walkthrough.md"
