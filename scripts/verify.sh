#!/bin/sh
# TokenTrack: run the regression suites against the running Docker Compose stack.
#
#   ./scripts/verify.sh                 # static checks, unit, integration and browser suites
#   ./scripts/verify.sh backend         # Rails + Kotlin only
#   ./scripts/verify.sh frontend        # lint, typecheck, unit tests
#   ./scripts/verify.sh browser         # the eight Playwright workflows
#
# Browser suites run in a fixed order: `requests` must precede `budgets`, because the budgets workflow revises
# Jordan's allowance and Rails then (correctly) refuses to approve a request submitted against the older revision.
# The projects, budgets and requests workflows write to the development database by design (one archived review
# project and one 3 USD conserved transfer per run); they never delete or rewrite history.
#
# Exit code: 0 when every selected suite passed, 1 otherwise. Every suite runs even if an earlier one fails.
set -u
cd "$(dirname "$0")/.."
COMPOSE="${DOCKER_COMPOSE:-docker compose}"
DOCKER="${DOCKER:-docker}"
PLAYWRIGHT_IMAGE="${PLAYWRIGHT_IMAGE:-mcr.microsoft.com/playwright:v1.56.1-noble}"
FAILED=""
PASSED=0

check() {
  name="$1"; shift
  printf '%-34s ' "$name"
  log="$(mktemp "${TMPDIR:-/tmp}/tokentrack-verify.XXXXXX")"
  if "$@" >"$log" 2>&1; then PASSED=$((PASSED + 1)); printf 'ok\n'; rm -f "$log"
  else FAILED="$FAILED\n  $name (log: $log)"; printf 'FAILED\n'; tail -n 15 "$log" | sed 's/^/    /'; fi
}
frontend() { $COMPOSE exec -T frontend "$@"; }

run_frontend() {
  check "frontend lint" frontend npm run -s lint
  check "frontend typecheck" frontend npm run -s typecheck
  check "frontend unit tests" frontend npm test
}
run_backend() {
  check "rails autoload check" $COMPOSE exec -T core-api bin/rails zeitwerk:check
  check "rails rspec" $COMPOSE exec -T core-api bundle exec rspec
  check "kotlin unit tests" $COMPOSE exec -T usage-engine gradle test
  check "kotlin postgres integration" $COMPOSE exec -T usage-engine gradle integrationTest
}
# The frontend development image has no browser. Suites run in the pinned Playwright image, attached to the
# Compose network so they reach the app (and prove the Kotlin internal routes reject them) by service name.
playwright() {
  $DOCKER run --rm --network "$NETWORK" -e BASE_URL=http://frontend:3000 -v "$PWD/frontend:/app" -w /app "$PLAYWRIGHT_IMAGE" "$@"
}
run_browser() {
  container="$($COMPOSE ps -q frontend 2>/dev/null | head -n 1)"
  [ -n "$container" ] || { echo "frontend is not running; start the stack first" >&2; exit 69; }
  NETWORK="$($DOCKER inspect -f '{{range $name, $_ := .NetworkSettings.Networks}}{{$name}}{{end}}' "$container")"
  # Host-side dependencies for the runner image, separate from the Compose dependency volume.
  [ -d frontend/node_modules/playwright ] || check "browser: install test dependencies" playwright npm ci
  for suite in browser access projects analytics requests budgets agents agent-insights; do
    check "browser: $suite" playwright npm run -s "test:$suite"
  done
}

case "${1:-all}" in
  frontend) run_frontend ;;
  backend) run_backend ;;
  browser) run_browser ;;
  all) run_frontend; run_backend; run_browser ;;
  *) echo "Usage: scripts/verify.sh [all|frontend|backend|browser]" >&2; exit 64 ;;
esac

if [ -n "$FAILED" ]; then printf '\n%s passed; failed:%b\n' "$PASSED" "$FAILED"; exit 1; fi
printf '\nAll %s checks passed.\n' "$PASSED"
