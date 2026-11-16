# Local development

## Start and stop

Install Docker Desktop with Compose and Git. Host Node, Ruby, Java, Gradle, and PostgreSQL are not required. Ensure ports 3000, 3001, 8080, and 5432 are available.

```bash
cp .env.example .env
# Edit .env: replace the three example passwords, USAGE_REFERENCE_TOKEN and USAGE_FINANCIAL_TOKEN.
# Generate each independent backend-only token: openssl rand -hex 32
docker compose up --build -d
# Required on a fresh database; safe to repeat:
docker compose exec core-api bin/rails db:migrate db:seed
docker compose exec -e RAILS_ENV=test core-api bin/rails db:migrate
```

Initial builds download dependencies. The frontend can show an unavailable status while services boot. After migrating/seeding, open <http://localhost:3000> and choose an organization and identity. Use the header menu to switch; page refresh restores the HTTP-only demo session. Stop containers with:

```bash
docker compose down
# Start again:
docker compose up --build -d
docker compose ps
docker compose logs --tail=100
```

`.env` is ignored. Do not commit real passwords, Rails keys, or credentials. Environment examples contain explicitly non-sensitive placeholders. The initialization script creates roles, both schemas, and the Rails test database on first volume startup. The Rails migration and seed commands above are still required; Flyway applies usage migrations when Kotlin starts. Demo entry expects these business tables to exist; health checks test connectivity independently.

## Services and variables

| Service | Default address | Host-port variable |
| --- | --- | --- |
| Frontend | <http://localhost:3000> | `FRONTEND_PORT` |
| Rails health | <http://localhost:3001/api/v1/health> | `CORE_API_PORT` |
| Kotlin health | <http://localhost:8080/actuator/health> | `USAGE_ENGINE_PORT` |
| PostgreSQL | `localhost:5432` | `POSTGRES_PORT` |

All host ports bind to `127.0.0.1`. Changing host ports does not change container ports or Docker service addresses.

| Variables | Purpose |
| --- | --- |
| `POSTGRES_DB`, `POSTGRES_TEST_DB` | Development and isolated backend test database names |
| `POSTGRES_USER`, `POSTGRES_PASSWORD` | Bootstrap administrator; supplied only to PostgreSQL |
| `CORE_DB_USER`, `CORE_DB_PASSWORD` | Rails login, owns `business` |
| `USAGE_DB_USER`, `USAGE_DB_PASSWORD` | Kotlin login, owns `usage` |
| `FRONTEND_ORIGIN` | Exact allowed CORS origin; update if changing the frontend port |
| `CORE_API_URL`, `USAGE_ENGINE_URL` | Server-only Next.js base URLs; Docker defaults use service names |
| `USAGE_REFERENCE_TOKEN` | Shared backend-only credential, at least 32 characters; generate with `openssl rand -hex 32`, store only in ignored .env |
| `RAILS_REFERENCE_URL` | Kotlin-to-Rails internal base URL; Compose uses http://core-api:3001 |
| `USAGE_TEST_DB_NAME` | Kotlin integration database; Compose derives it from POSTGRES_TEST_DB, distinct from DB_NAME |
| `DEMO_AUTH_ENABLED` | Demo entry/seed/reset switch; Compose defaults true, Rails production always disables it |

Compose maps the role variables to each backend's `DB_USER`/`DB_PASSWORD`, plus `DB_HOST`, `DB_PORT`, and `DB_NAME`. Rails additionally receives `DB_TEST_NAME`. No PostgreSQL configuration or reference-service credential is supplied to Next.js. The reference credential is separate from database passwords and demo cookies. Existing .env files must add it before rebuilding; never use the checked-in placeholder as a credential.

## Toolchains and source changes

The reproducible container toolchains are Node 24, Ruby 3.4, Gradle 8.14.3, JDK 21, and PostgreSQL 17. Frontend and Ruby dependency versions are locked; Gradle dependency locks and a wrapper are checked in. Framework versions are listed in the manifests and verification report.

Next.js and Rails reload source changes. Kotlin uses mounted sources and Gradle `bootRun`: restart after edits with `docker compose restart usage-engine`. Its DevTools dependency can reload compiled classes, but this setup does not promise automatic source compilation. Gradle rebuilds changed code on restart.

Named volumes cache frontend dependencies and `.next`, Ruby gems, Gradle dependencies, and Kotlin build output. Frontend startup runs `npm ci` to synchronize its dependency volume; Rails checks/installs the locked bundle. Rebuild after dependency changes with `docker compose up --build -d`. Host `node_modules` or host-compiled gems never override container dependencies.

Demo selection requires active flagged identities in flagged demo tenants. Sessions expire after eight hours and are revoked on switching/logout. Changes to role state are resolved by Rails; the browser stores only a cookie and theme preference, with organization data cached in memory. See [architecture.md](architecture.md) for scope and cache rules.

For host frontend development, install Node 24 and run in `frontend/`:

```bash
npm ci
CORE_API_URL=http://localhost:3001 USAGE_ENGINE_URL=http://localhost:8080 npm run dev
```

Stop the Compose frontend first to free port 3000. Host Rails uses Ruby 3.4, a PostgreSQL client for SQL snapshots, `bundle install`, the `DB_*` variables above, `DEMO_AUTH_ENABLED=true`, and `bin/rails server -p 3001`. Host Kotlin uses JDK 21 and `./gradlew bootRun` with the usage role's `DB_*` variables. A host JDK 25 is not used for the pinned Gradle 8 toolchain. Compose is the verified primary workflow.

## Usage ingestion and reports

Rebuild after adding the backend credential: `docker compose up --build -d`. The usage role already owns the usage schema in development/test databases. Flyway creates its history and versioned tables inside that schema with create-schemas=false and clean disabled. No administrator credential is given to Kotlin. Migrations remain under `services/usage-engine/src/main/resources/db/migration`; introduce a new version rather than editing an applied migration. Rails structure.sql remains business-only.

The demo workload is generated from the company spec and a Rails snapshot (see [demo data](enterprise-demo-data.md)):

```bash
./scripts/generate-enterprise-demo.sh --profile demo --seed 42
docker compose exec usage-engine sh -c 'bin/usage import /app/demo/enterprise/generated/demo-seed42/memento-ai/usage-*.csv --source enterprise-memento-v1'
# Run the same command again: zero inserts, existing events counted as duplicates.
docker compose exec usage-engine bin/usage list
docker compose exec usage-engine bin/usage report BATCH_UUID --offset 0 --limit 100
```

`import` and `agent-import` accept several files in one call (one JVM start); each file is still its own batch with its own report. A completed import with rejected rows exits 2; a malformed or partial import exits 3, keeping the complete rows read before the problem. The Kotlin ingestion tests cover invalid, duplicate, conflicting and malformed input against PostgreSQL.

CLI stdout contains structured JSON; compiler/runtime diagnostics go to stderr. bin/usage compiles using the container's pinned Gradle/JDK and launches a non-web process with DevTools restart disabled. Database migrations also apply in the CLI. Use bin/usage help without connecting to the database. Exit 0 means success (including identical duplicates); 2 means completed with rejected rows; 3 means partial/fatal/infrastructure failure; 64 means invalid arguments or unknown report batch. No upload endpoint or new dashboard exists.

Use a stable source namespace across retries, not the filename or current timestamp. Changing the source deliberately creates a separate identity namespace. Each accepted event retains its first import batch and payload. Reports show all error-code counts and up to 100 persistent rejection details per page, never raw rows or private text. Separate sources used by verification fixtures remain visible in reports.

A caught infrastructure failure finalizes partial/failed metadata where possible. If the database is unavailable or the process is killed, running batches become detectably interrupted after fifteen minutes without a committed heartbeat, reconciled by import/list/report. Retrying the original file/source is safe; do not delete events or manually rewrite counts. No total is claimed for unread input. See [CSV and count semantics](../contracts/usage-event-v1.md).

Demo resets affect business data only; they do not clear immutable usage. Regenerate from a fresh snapshot after a reset and understand that changed generator inputs produce different event IDs. Do not use destructive resets to demonstrate replay. Tests clean up only their own isolated usage test records.

## Checks

With Compose running:

```bash
docker compose exec frontend npm run lint
docker compose exec frontend npm run typecheck
docker compose exec frontend npm test
docker compose exec core-api bundle exec rspec
docker compose exec usage-engine gradle test
docker compose exec usage-engine gradle integrationTest
curl -i http://localhost:3001/api/v1/health
curl -i http://localhost:8080/actuator/health
curl -i http://localhost:3000/api/health
```

For a reproducible Chromium smoke check of themes, desktop/mobile layout, navigation, and real status cards, use the matching browser image (no browser installation on the host is necessary):

```bash
docker run --rm -v "$PWD/frontend:/app" -w /app node:24-bookworm-slim npm ci
docker run --rm --network tokentrack_default \
  -e BASE_URL=http://frontend:3000 \
  -v "$PWD/frontend:/app" -w /app \
  mcr.microsoft.com/playwright:v1.56.1-noble npm run test:browser
# Four personas, project edits, cache isolation, authorization, and responsive UI:
docker run --rm --network tokentrack_default \
  -e BASE_URL=http://frontend:3000 \
  -v "$PWD/frontend:/app" -w /app \
  mcr.microsoft.com/playwright:v1.56.1-noble npm run test:access
# Create/staff/transfer/archive a real project; leaves an archived review record:
docker run --rm --network tokentrack_default \
  -e BASE_URL=http://frontend:3000 \
  -v "$PWD/frontend:/app" -w /app \
  mcr.microsoft.com/playwright:v1.56.1-noble npm run test:projects
```

This uses `frontend/node_modules`, installed by the first command independently of Compose's dependency volume. Shell/access screenshots are written to `/tmp/tokentrack-browser`, and project screenshots to another `/tmp` folder, in the test container; bind-mount that directory to preserve them. Add `-e EXPECT_USAGE_DOWN=1` while usage-engine is stopped to check the visible failure state. The browser check is optional for normal startup.

Rails specs use real PostgreSQL in `tokentrack_test`, seed before the suite, and roll ordinary examples back. The concurrent-transfer spec uses separate committed connections and explicitly cleans up its own generated project. They cover relationships, constraints, grants, tenant scope, sessions, project edits, membership periods, creation, staffing, lifecycle, atomic transfer/revocation, concurrency, and health. Connection failure specs simulate errors; live outage checks separately exercise PostgreSQL. Kotlin application/Actuator tests use an in-memory H2 database with the usage schema and a failing DataSource for the negative case; Flyway is disabled only for these health tests. Parser, validator, reference HTTP-client, and generator tests run in the unit suite. The tagged integrationTest task always executes real Flyway/PostgreSQL tests in USAGE_TEST_DB_NAME using the restricted usage role, covering uniqueness, concurrent imports, chunk rollback, partial retries, durable diagnostics, and business-schema denial. It refuses the development database. No Testcontainers daemon access or new database creation privilege is needed. Live Compose checks separately verify PostgreSQL and full database outages. Frontend tests cover actual response contracts, invalid bodies, invalid JSON, timeouts, and network failures.

Inspect schema ownership without printing passwords:

```bash
docker compose exec postgres sh -c 'psql -U "$POSTGRES_USER" -d "$POSTGRES_DB" -c "\\dn"'
```

Stop Kotlin to exercise frontend degradation. Within the next refresh, Usage Engine becomes disconnected and the database confirmation becomes unavailable; Core API can remain connected:

```bash
docker compose stop usage-engine
curl -i http://localhost:3000/api/health
docker compose start usage-engine
```

For a full database outage, `docker compose stop postgres`, call both backend endpoints (expect 503), and `docker compose start postgres`. Each backend recovers without claiming a successful connection during the outage. Do not run tests while intentionally stopping the database.

Build production artifacts independently of the running development mount:

```bash
docker build --target production -t tokentrack-frontend:production frontend
docker build --target production -t tokentrack-core-api:production services/core-api
docker build --target production -t tokentrack-usage-engine:production services/usage-engine
```

These image builds do not deploy anything. Rails production needs a separately supplied `SECRET_KEY_BASE`; application databases, credentials, and URLs must also be configured at runtime.

## Migrations and demo resets

Rails roles intentionally cannot create/drop databases or alter the other service's schema. Database creation is a bootstrap administrator task. Introduce business tables with conventional Rails migrations:

```bash
# Example for a future change; do not regenerate the existing organization tables:
docker compose exec core-api bin/rails generate migration AddTimezoneToOrganizations timezone:string
# Edit the migration before applying it.
docker compose exec core-api bin/rails db:migrate
docker compose exec -e RAILS_ENV=test core-api bin/rails db:migrate
```

PostgreSQL-specific checks/triggers are preserved in `db/structure.sql`. The schema dump task omits `CREATE SCHEMA business` because Docker initializes that schema and the app role cannot create database-level schemas. Standard `db:migrate`/`db:schema:dump` commands maintain this automatically. Do not manually edit the snapshot or initialization SQL to evolve tables.

`db:seed` is transactional and repeatable: it restores the declared fictional fixture attributes without duplication. To intentionally discard demo edits and sessions while preserving non-demo tenants:

```bash
docker compose exec core-api bin/rails demo:reset
```

Both seed/reset require demo mode in development/test. All organizational and project entities live in the business schema; usage events, import batches and rejections live in the usage schema.

Migration `20261109000100` preserves existing IDs, adds creator/restore metadata and membership periods, and checks administrator integrity with deferred PostgreSQL triggers. Its rollback is intentionally irreversible: multiple historical periods must be reconciled before restoring the old all-time uniqueness rule. Review/back up real data before adapting demo migrations outside this local workflow.

Project creation requires an organization-scoped `project_creator` grant; the seed gives one to each company's leader and project-lead persona (for example Amara Lindqvist and Mateo Alvarez). Existing `project_lead` grants explicitly authorize staffing/lifecycle/transfer on that project. `owner` and `lead` membership labels alone do not. Archived projects are read-only until restored. Use the UI to transfer before removing the final administrator. The API has no project-delete action. Browser project checks retain an archived `Review Collaboration ...` review project/history, restore Mateo's administration, and close other contributors' periods. Repeated runs add review projects; `demo:reset` deliberately removes all demo edits if a clean fixture set is needed.

The development migration-check middleware is disabled so a database outage can always reach the health controller and return structured JSON. Run migration commands explicitly after adding migrations. Avoid `db:reset`, `db:create`, or `db:drop` with the restricted application role. Flyway now manages Kotlin tables; do not edit database initialization SQL or Rails snapshots for usage changes.

## Reset and troubleshooting

`docker compose down` preserves all named volumes. `docker compose restart <service>` restarts one service. For a **destructive local reset**, the following deletes both databases and all dependency caches:

```bash
docker compose down -v
docker compose up --build -d
docker compose exec core-api bin/rails db:migrate db:seed
docker compose exec -e RAILS_ENV=test core-api bin/rails db:migrate
```

To reset only the database while keeping dependency caches, stop the stack and remove its database volume explicitly. This also destroys the Rails test database:

```bash
docker compose down
docker volume rm tokentrack_postgres_data
docker compose up --build -d
docker compose exec core-api bin/rails db:migrate db:seed
docker compose exec -e RAILS_ENV=test core-api bin/rails db:migrate
```



- **Port already allocated:** set the corresponding port variable in `.env`; update `FRONTEND_ORIGIN` when changing the UI port.
- **Password authentication failed after editing `.env`:** initialization runs only on a fresh volume. Restore matching credentials, rotate roles explicitly as administrator, or perform the documented destructive database reset if data is disposable.
- **Picker fails after a fresh setup:** run `docker compose exec core-api bin/rails db:migrate db:seed`; confirm `DEMO_AUTH_ENABLED=true`. Rails production intentionally refuses demo entry.
- **401 after a reset or eight hours:** choose an identity again. Reset/switch/logout revokes sessions.
- **403 on selection or project updates:** use the same-origin UI, check `FRONTEND_ORIGIN` matches the browser URL, and confirm an explicit project lead grant for edits/staffing and project_creator grant for creation. Restore archived projects before staffing.
- **Backend unreachable:** use `docker compose ps` and `docker compose logs core-api usage-engine postgres --tail=100`. Initial Kotlin dependency resolution may take a few minutes.
- **Docker socket access or daemon error:** start Docker Desktop and ensure your terminal can run `docker info`.
- **Frontend shows an error:** `/api/health` reports each service independently. A malformed response is an error; an unreachable service is disconnected. Database status means both backend connections are verified, not a direct browser query.
- **Gradle cache/build problems:** stop usage-engine, then remove only `tokentrack_usage_gradle` or `tokentrack_usage_build` and rebuild. Do not delete the database volume to repair a build.
- **Credentials in logs:** do not print `.env`, run interpolated `docker compose config` in shared logs, or share connection URLs containing passwords. `docker compose config --quiet` validates without printing values.

## Demo data, pricing and finance operations

```bash
docker compose up --build -d
./scripts/setup-demo.sh                # idempotent; exit 0 ready, 1 a step failed, 64 bad arguments, 69 a service is unavailable
./scripts/setup-demo.sh --profile smoke   # ~10% subset; use one profile per database
./scripts/verify.sh                    # or: frontend | backend | browser
docker compose exec core-api bin/rails enterprise_demo:summary
```

`setup-demo.sh` runs, in order: Rails migrations (development and test), `generate-enterprise-demo.sh` (seed, snapshot, generate), `load-prices` (catalogue and synthetic historical rates), `enterprise_demo:fund`, one `import` per company, `price` per source, `deliver` until the outbox drains, one `agent-import` per company, `enterprise_demo:controls`, `agents:demo_correction`, then `reconcile` with zero-discrepancy checks. Each step's output is kept in a temporary log directory printed on the first line. Set `DOCKER_COMPOSE` to target another Compose project, and `DOCKER` / `PLAYWRIGHT_IMAGE` for `verify.sh`.

`demo/enterprise/companies-v1.json` (built by `demo/enterprise/build-spec.py`) is the single source for both services: Rails expands it into units, people, reporting lines, dated project memberships, grants and the funding plan (`enterprise_demo:seed`, `:fund`, `:controls`; `COMPANY=slug` limits them); Kotlin reads it with the Rails snapshot to write the workload. The start date is configurable only before the companies are seeded, because membership dates are recorded once and never rewritten.

`price` processes only unpriced records and never rewrites usage or existing price snapshots; it exits 2 because the demo deliberately includes a self-hosted model with no pricing profile. `load-prices --file /app/custom.json` loads additional catalogue records and rejects conflicting IDs (see [schedule closure](model-pricing.md)). Delivery exit 2 reports retry or dead work; due retries need another `deliver`, and `deliver --retry-dead true` starts another bounded cycle after a permanent failure is repaired. `reconcile` exits 2 for "balanced with unpriced usage" and 3 for a discrepancy.

Local trusted financial operations (the actor needs an explicit financial_operator grant, for example Northline's Gabriel Moreau):

```bash
docker compose exec core-api env ACTOR_ID=ACTOR_UUID MONTH=2026-10 bin/rails finance:report
docker compose exec core-api env ACTOR_ID=ACTOR_UUID ACCOUNT_ID=RESERVE_UUID MONTH=2026-10 AMOUNT=1000 REQUEST_KEY=unique-funding-key REASON='Explicit demo funding' bin/rails finance:fund
docker compose exec core-api env ACTOR_ID=ACTOR_UUID FROM_ACCOUNT_ID=UNIT_ACCOUNT_UUID TO_ACCOUNT_ID=PROJECT_ACCOUNT_UUID MONTH=2026-10 AMOUNT=300 REQUEST_KEY=unique-transfer-key REASON='Project allocation' bin/rails finance:transfer
docker compose exec core-api env ACTOR_ID=ACTOR_UUID TRANSACTION_ID=CHARGE_UUID AMOUNT=0.1 REQUEST_KEY=unique-correction-key REASON='Explicit synthetic correction' bin/rails finance:correct
```

Omit AMOUNT for a reversal without replacement. Money inputs are decimal strings. Reuse a request key only for the identical operation. Demo reset refuses organizations with financial, request or spending-control history; preserve the volume and audit trail.

Optional budget warning thresholds in `.env`: `BUDGET_WARNING_APPROACHING_PERCENT=75` and `BUDGET_WARNING_HIGH_PERCENT=90` (0 < approaching < high < 100; recreate core-api after changes). Agent insight thresholds are under `tokentrack.agent-insights` in the usage engine's `application.yml`; `AGENT_INSIGHTS_MIN_RUNS` and `AGENT_INSIGHTS_MIN_RUNS_LIMITED` override the sample sizes.

## Tests

```bash
docker compose exec core-api bin/rails zeitwerk:check
docker compose exec core-api bundle exec rspec          # seeds Northline Financial and Memento AI into the test database
docker compose exec usage-engine gradle test integrationTest
docker compose exec frontend npm run lint
docker compose exec frontend npm run typecheck
docker compose exec frontend npm test
./scripts/verify.sh browser                              # Playwright suites in the pinned image
```

Rails specs address people by persona (`person("employee")` is Hana Takeda at Northline; see `spec/support/demo_helpers.rb`). Kotlin integration tests use the isolated test database and clean up only their own records.

Browser suites run against the loaded development demo (Northline Financial, October 2026) and must run with `requests` before `budgets`: the budgets workflow revises Hana's allowance, which a pending request depends on. `verify.sh` keeps that order. They write real local history by design: an archived review project per run, immutable allowance revisions, an idempotent 25 USD and a new 3 USD reviewed transfer per budgets run, and the approvals the requests workflow performs. The frontend development container has no browser; use `verify.sh browser` or:

```bash
docker run --rm --network tokentrack_default -e BASE_URL=http://frontend:3000 \
  -v "$PWD/frontend:/app" -w /app mcr.microsoft.com/playwright:v1.56.1-noble npm run test:agent-insights
```

## Docker resource notes

- Every `bin/usage` call starts a JVM with a Spring context (~2 s). It skips Gradle's ~5 s up-to-date check when no source or build file is newer than the last compile; set `USAGE_CLI_REBUILD=1` to force it.
- Rails logs at `info` in Compose (`RAILS_LOG_LEVEL`); `debug` writes every SQL statement to the bind-mounted log, hundreds of MB per demo load. `RAILS_MAX_THREADS` (default 5) sets Puma threads and the database pool.
- The stack needs about 2 GB of memory when idle and more while loading. Docker Desktop's default 8 GB fits one stack; a second Compose project at the same time can push the VM into out-of-memory kills (exit 137), so stop one with `docker compose -p NAME down` first.
