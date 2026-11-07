# Slice 1 implementation and verification

Verified locally on **November 7, 2026**, on macOS/Apple Silicon with Docker Desktop. This report distinguishes executed checks from future work.

## What changed

| Area | Implementation |
| --- | --- |
| Frontend | Next.js App Router, strict TypeScript, Tailwind tokens, shadcn/ui-style Button/Badge and Radix Tooltip, Lucide, bundled Geist fonts, desktop/mobile shell, persistent themes, intentional planned-feature empty states, loading/error/404 handling |
| Rails | Conventional API-only scaffold, PostgreSQL `business` search path, exact-origin CORS, versioned health controller, RSpec request specs |
| Kotlin | Spring Boot/Kotlin scaffold, Gradle Kotlin DSL/wrapper/locks, PostgreSQL `usage` connection pool, standard Actuator database health, JUnit application/health tests |
| Infrastructure | Four-service Compose, development and production image stages, persistent database, separate schema roles, isolated Rails test database, source mounts and dependency caches, configurable loopback ports, ignored local environment |
| Documentation | Existing product vision preserved and implementation status corrected; current architecture, setup, troubleshooting, contract boundaries, demo scope, and this report added |

No business models, authentication, budget calculations, ingestion, event delivery, analytics, or external deployment were added.

## Toolchain selection

The host initially had Ruby 4.0.9, Bundler 4.0.23, JDK 25, Docker 29.9.2, and Compose 5.6.1. Node, npm, Gradle, and PostgreSQL client tools were not on PATH. To avoid depending on those host differences, builds and tests use container toolchains.

| Component | Selected version |
| --- | --- |
| Node | 24 image line |
| Next.js / React | 16.4.5 / 19.3.1 |
| TypeScript / Tailwind | 5.9.3 / 4.3.5 |
| Geist | 1.9.2, bundled locally |
| Ruby / Rails | 3.4.12 / 8.1.4.1 |
| Kotlin / Spring Boot | 2.2.21 / 3.5.16 |
| JDK / Gradle | 21 / 8.14.3 |
| PostgreSQL | 17.11 from the 17 image line |

Compatibility was checked against the official [Next.js 16 runtime requirements](https://nextjs.org/docs/app/guides/upgrading/version-16), [Rails Ruby requirements](https://github.com/rails/rails/blob/main/guides/source/upgrading_ruby_on_rails.md), [Rails releases](https://www.rubyonrails.org/releases), and [Spring Boot 3.5 system requirements](https://docs.spring.io/spring-boot/3.5/system-requirements.html), then exercised through builds and runtime checks. Application dependencies are locked; base image patch tags can advance within their pinned major/toolchain lines.

## Executed checks

| Check | Actual result |
| --- | --- |
| `docker compose config --quiet` | Passed without printing interpolated secrets |
| `docker compose build` | All three application development images built |
| `docker compose up -d` | Four services started; PostgreSQL became healthy on a fresh volume |
| `docker compose down` then `docker compose up --build -d` | Clean shutdown/rebuild/start completed; schema owners persisted in the named database volume |
| PostgreSQL schema and role queries | `business` owned by core role, `usage` owned by usage role; neither role can use/create in the other schema or `public`; neither is superuser or can create databases |
| Domain table inspection | No tables in either application schema on initial startup |
| Rails `GET /api/v1/health` | HTTP 200, `core-api`, `ok`, `database: connected` |
| Kotlin `GET /actuator/health` | HTTP 200, overall `UP`, database component `UP`, no connection details exposed |
| Backend CORS checks | Both live endpoints permit the configured `http://localhost:3000` origin |
| Next.js `GET /api/health` | HTTP 200; core, usage, and database all connected; no-store caching |
| `docker compose exec core-api bundle exec rspec` | **5 examples, 0 failures**, using PostgreSQL test database; healthy JSON, three failure classes, and CORS covered |
| `docker compose exec usage-engine gradle test` | **2 tests, 0 failures**; application starts, real H2 connectivity reports UP, failing DataSource reports DOWN/503 |
| `docker compose exec frontend npm run lint` | Passed with no lint warnings |
| `docker compose exec frontend npm run typecheck` | Passed strict TypeScript checking and Next.js route type generation |
| `docker compose exec frontend npm test` | **5 tests passed**; response contracts, malformed/invalid JSON, unreachable services, timeouts, and combined database confirmation |
| `npm audit` | **0 reported vulnerabilities**, including development dependencies |
| Production image builds for all three applications | Passed; Next.js standalone, Rails production stage, Kotlin bootJar/JRE stage |
| Production runtime checks | All three production images started on the private network as non-root users; complete browser smoke passed against production frontend and backends; temporary containers and credential files removed afterward |
| Git-visible file scan | Generated local password values absent from every non-ignored file; `.env` ignored; no Rails master key retained |
| `git diff --check` | Passed |
| Final container log inspection | No startup/runtime exceptions after the final rebuild/start |

## Browser checks

The checked-in `frontend/e2e/smoke.mjs` ran in Chromium using the matching Playwright 1.56.1 container. It passed against development and production runtimes:

- Visible real connectivity for both APIs and PostgreSQL.
- Desktop at 1440px and mobile at 390px, with no horizontal overflow on mobile.
- Light and dark rendering, toggle behavior, and local theme persistence across reload.
- Eight intentionally disabled planned navigation items.
- Mobile navigation opens and closes after choosing Overview.
- Manual status refresh and recovery from a missing route.
- No browser runtime exceptions.

Desktop/mobile screenshots were captured outside the repository under `/private/tmp/tokentrack-browser/` and visually inspected. The interface uses restrained neutral surfaces, thin borders, readable status labels with icons, and no fabricated financial metrics. Browser automation covers Chromium; Safari/Firefox and a formal accessibility audit were not run.

## Negative paths and recovery

**Stopped usage-engine:** the Next.js aggregate returned HTTP 503, Core API stayed connected, Usage Engine became disconnected, and database confirmation became unavailable. A separate browser run with `EXPECT_USAGE_DOWN=1` verified those visible cards and captured the result. Starting Kotlin restored all healthy states.

**Stopped PostgreSQL:** live Rails returned HTTP 503 with `database: disconnected`; Kotlin returned HTTP 503 with `components.db.status: DOWN`; Next.js returned HTTP 503 with both backend errors and database disconnected. Restarting PostgreSQL restored all three healthy responses without restarting either application. This checks real PostgreSQL failure in addition to mocked test failures.

Expected connection errors occurred during these intentional outages. They were not treated as successful responses or hidden behind stale green status indicators.

## Limits and follow-up decisions

- This is a local development foundation, not a cloud deployment. Production image runtime checks do not establish production security, hosting, tenant isolation, or service authentication.
- Kotlin source changes require `docker compose restart usage-engine` to compile reliably. Next.js and Rails reload mounted sources automatically.
- ESLint 9.39.5 matches the peer ranges of Next.js's bundled React/accessibility/import plugins. npm marks ESLint 9 deprecated; moving to ESLint 10 should wait for compatible plugin peer ranges. A scoped override updates the TypeScript parser's transitive minimatch to the patched 11 line; lint, types, builds, and the dependency audit pass with it.
- JUnit uses H2 for fast in-process tests; PostgreSQL-specific behavior was checked separately through the running Compose stack. No host-native backend workflow, cross-platform Docker build, or load testing was performed.
- Future tables need framework migrations; initialization scripts do not rerun on existing volumes. Credentials changed in `.env` do not automatically rotate existing PostgreSQL roles.
- Authentication and authorization design remain decisions for Slice 2. The Developer label is a placeholder and provides no identity or access-control behavior.

## Beginner walkthrough and next slice

1. Opening `localhost:3000` loads the Next.js shell. Theme selection persists in the browser. The status component requests the same-origin `/api/health` endpoint on load and every fifteen seconds.
2. Next.js calls Rails over the Docker network at `core-api:3001/api/v1/health`; Rails runs `SELECT 1` using its own PostgreSQL login.
3. In parallel, Next.js calls Kotlin at `usage-engine:8080/actuator/health`; Actuator checks the JDBC connection pool using Kotlin's own login.
4. Both logins connect to the same PostgreSQL database. Rails resolves objects in `business`; Kotlin resolves objects in `usage`. Permissions keep their writes separate.
5. Next.js validates both responses and reports database connectivity only when both connections are confirmed. Internal URLs and database credentials stay out of the browser.
6. Slice 2 can introduce organizations, users, memberships, and scoped roles through Rails migrations, versioned APIs, and authorization specs, then connect those APIs to the existing shell. Later usage ingestion and pricing belong in Kotlin; authoritative financial posting and approvals belong in Rails. Neither path is implemented prematurely.
