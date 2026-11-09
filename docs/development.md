# Local development

## Start and stop

Install Docker Desktop with Compose and Git. Host Node, Ruby, Java, Gradle, and PostgreSQL are not required. Ensure ports 3000, 3001, 8080, and 5432 are available.

```bash
cp .env.example .env
# Edit .env: replace the three example passwords with different local values.
docker compose up --build -d
# Required on a fresh database; repeat safely when setting up Slice 2:
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

`.env` is ignored. Do not commit real passwords, Rails keys, or credentials. Environment examples contain explicitly non-sensitive placeholders. The initialization script creates roles, both schemas, and the Rails test database on first volume startup. Slice 2 requires the Rails migration/seed commands above. Demo entry expects these business tables to exist; health checks test connectivity independently.

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
| `POSTGRES_DB`, `POSTGRES_TEST_DB` | Development and isolated Rails test database names |
| `POSTGRES_USER`, `POSTGRES_PASSWORD` | Bootstrap administrator; supplied only to PostgreSQL |
| `CORE_DB_USER`, `CORE_DB_PASSWORD` | Rails login, owns `business` |
| `USAGE_DB_USER`, `USAGE_DB_PASSWORD` | Kotlin login, owns `usage` |
| `FRONTEND_ORIGIN` | Exact allowed CORS origin; update if changing the frontend port |
| `CORE_API_URL`, `USAGE_ENGINE_URL` | Server-only Next.js base URLs; Docker defaults use service names |
| `DEMO_AUTH_ENABLED` | Demo entry/seed/reset switch; Compose defaults true, Rails production always disables it |

Compose maps the role variables to each backend's `DB_USER`/`DB_PASSWORD`, plus `DB_HOST`, `DB_PORT`, and `DB_NAME`. Rails additionally receives `DB_TEST_NAME`. No PostgreSQL configuration is supplied to Next.js.

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

## Checks

With Compose running:

```bash
docker compose exec frontend npm run lint
docker compose exec frontend npm run typecheck
docker compose exec frontend npm test
docker compose exec core-api bundle exec rspec
docker compose exec usage-engine gradle test
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
```

This uses `frontend/node_modules`, installed by the first command independently of Compose's dependency volume. Screenshots are written to `/tmp/tokentrack-browser` in the test container; bind-mount that directory to preserve them. Add `-e EXPECT_USAGE_DOWN=1` while usage-engine is stopped to check the visible failure state. The browser check is optional for normal startup.

Rails specs use real PostgreSQL in `tokentrack_test`, seed before the suite, and roll each example back. They cover relationships, constraints, grants, tenant scope, sessions, project edits, and health. Connection failure specs simulate errors; live outage checks separately exercise PostgreSQL. Kotlin's application/Actuator tests use an in-memory H2 database with the `usage` schema and a failing DataSource for the negative case. Live Compose checks separately verify PostgreSQL and full database outages. Frontend tests cover actual response contracts, invalid bodies, invalid JSON, timeouts, and network failures.

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

These image builds do not deploy anything. Rails production needs a separately supplied `SECRET_KEY_BASE`; application databases, credentials, and URLs must also be configured at runtime. See [slice2.md](slice2.md) for current executed checks and limits; [verification.md](verification.md) preserves the earlier Slice 1 report.

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

Both seed/reset require demo mode in development/test. All Slice 2 entities are in `business`; `usage` remains without domain tables.

The development migration-check middleware is disabled so a database outage can always reach the health controller and return structured JSON. Run migration commands explicitly after adding migrations. Avoid `db:reset`, `db:create`, or `db:drop` with the restricted application role. When Kotlin first owns tables, add a normal schema migration tool rather than editing initialization SQL.

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

Destructive volume resets and host-native service commands were not executed during Slice 2 verification; Compose migrations, repeatable seeds, and the demo-only reset in the isolated test database were tested.

- **Port already allocated:** set the corresponding port variable in `.env`; update `FRONTEND_ORIGIN` when changing the UI port.
- **Password authentication failed after editing `.env`:** initialization runs only on a fresh volume. Restore matching credentials, rotate roles explicitly as administrator, or perform the documented destructive database reset if data is disposable.
- **Picker fails after a fresh setup:** run `docker compose exec core-api bin/rails db:migrate db:seed`; confirm `DEMO_AUTH_ENABLED=true`. Rails production intentionally refuses demo entry.
- **401 after a reset or eight hours:** choose an identity again. Reset/switch/logout revokes sessions.
- **403 on selection or project updates:** use the same-origin UI, check `FRONTEND_ORIGIN` matches the browser URL, and confirm an explicit project lead grant for metadata edits.
- **Backend unreachable:** use `docker compose ps` and `docker compose logs core-api usage-engine postgres --tail=100`. Initial Kotlin dependency resolution may take a few minutes.
- **Docker socket access or daemon error:** start Docker Desktop and ensure your terminal can run `docker info`.
- **Frontend shows an error:** `/api/health` reports each service independently. A malformed response is an error; an unreachable service is disconnected. Database status means both backend connections are verified, not a direct browser query.
- **Gradle cache/build problems:** stop usage-engine, then remove only `tokentrack_usage_gradle` or `tokentrack_usage_build` and rebuild. Do not delete the database volume to repair a build.
- **Credentials in logs:** do not print `.env`, run interpolated `docker compose config` in shared logs, or share connection URLs containing passwords. `docker compose config --quiet` validates without printing values.
