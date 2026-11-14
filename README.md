# TokenTrack

> A local-first, full-stack AI spend and execution intelligence platform.

TokenTrack makes AI usage understandable and governable. It ingests metered usage, applies versioned model pricing, attributes spend to people and cross-functional projects, posts authoritative financial records, and presents role-scoped analytics, budgets, funding workflows, and agent execution telemetry in one workspace.

Built as a portfolio-quality systems project, it emphasizes the parts that tend to be difficult in real internal platforms: tenant-aware authorization, immutable financial history, idempotent ingestion and delivery, explicit data ownership, and honest reporting when cost data is incomplete.

## What it demonstrates

- A complete TypeScript, Ruby, Kotlin, and PostgreSQL application—not a static dashboard.
- Role-aware product experiences for leadership, managers, project leads, and employees.
- Canonical usage ingestion with validation, durable diagnostics, deduplication, and deterministic synthetic fixtures.
- Effective-dated AI pricing with precise decimal arithmetic and immutable price provenance.
- An append-only, corrected financial ledger with idempotent delivery and reconciliation.
- Project-first cost attribution that supports cross-functional work without double-counting expenditure.
- Scoped analytics and agent-run efficiency reporting that distinguish observed facts from estimates.
- Budget allocation, personal allowance controls, delegated approval, and auditable funding requests.
- A reproducible local demo using only fictional organizations and synthetic data—no provider credentials or paid AI APIs.

## Product tour

After choosing a fictional demo identity, explore:

| Workspace | What it shows |
| --- | --- |
| Overview, organization, teams, people, and projects | Organizational hierarchy, project collaboration, and backend-enforced visibility boundaries. |
| Analytics | Token use, pricing coverage, corrected ledger expenditure, trends, model/tool breakdowns, project attribution, and ledger audit history. |
| Agents | Explicit run outcomes, attempts, retries, duration, linked usage, and corrected known cost; period comparisons, deterministic anomaly findings with evidence quality, and a cost-driver breakdown. |
| Budgets | Funded accounts, monthly allocations, personal allowances, run-rate controls, and financial history. |
| Requests | Allowance and funding requests routed to the appropriate delegated or financial authority. |

The app intentionally does **not** infer employee productivity from token consumption, estimate missing costs as facts, or make recommendations/predictions from the demo data.

## Architecture

```mermaid
flowchart LR
  Browser[Browser] -->|same-origin UI + BFF| Web[Next.js / React]
  Web -->|HTTP-only demo session| Rails[Rails API]
  Rails -->|scoped aggregate request<br/>separate service token| Kotlin[Kotlin / Spring Boot]
  Kotlin -->|reference validation<br/>separate service token| Rails
  Fixtures[Usage CSV + execution JSONL] -->|CLI import| Kotlin
  Kotlin -->|priced usage, idempotent delivery| Rails
  Rails --> Business[(PostgreSQL<br/>business schema)]
  Kotlin --> Usage[(PostgreSQL<br/>usage schema)]
```

| Layer | Stack | Responsibility |
| --- | --- | --- |
| Product UI | Next.js 16, React 19, TypeScript, Tailwind | Responsive workspaces, dark/light themes, route-aware client caching, narrow BFF proxy. |
| Business service | Ruby on Rails 8 API-only | Organizations, sessions, access policy, projects, budgets, approvals, and authoritative finance. |
| Usage service | Kotlin, Spring Boot, JDBC, Flyway | CSV/JSONL contracts, validation, imports, pricing, outbox delivery, agent telemetry, bounded aggregates. |
| Storage | PostgreSQL 17 | Separate `business` and `usage` schemas with separate service write ownership. |
| Local runtime | Docker Compose | Four-service development environment with loopback-only ports. |

### Boundaries that matter

- Browsers never call Kotlin internal analytics endpoints and never receive service credentials.
- Rails authorizes the population before Kotlin aggregates it; directory visibility does not become analytics authority.
- Rails owns financial truth. Kotlin reports operational and token facts; corrected cost is derived from posted ledger entries in Rails.
- Kotlin and Rails share a local PostgreSQL instance for convenience, but write only their own schema.
- Usage, execution, and financial data use stable identities, replay-safe operations, and immutable audit records where history matters.

For more detail, see [architecture](docs/architecture.md), [analytics contract](docs/analytics-contract.md), and the [agent execution contract](contracts/agent-execution-v1.md).

## Quick start

### Prerequisites

- Docker Desktop with Docker Compose
- `openssl` (to generate local service tokens)

```bash
cp .env.example .env
```

Edit `.env` before starting. Replace all three database password placeholders and generate distinct backend-only tokens:

```bash
openssl rand -hex 32
```

Use one generated value each for `USAGE_REFERENCE_TOKEN`, `USAGE_FINANCIAL_TOKEN`, and `USAGE_ANALYTICS_TOKEN`.

Start the stack and initialize the demo database:

```bash
docker compose up --build -d
docker compose exec core-api bin/rails db:migrate db:seed
docker compose exec -e RAILS_ENV=test core-api bin/rails db:migrate
```

| Service | Address |
| --- | --- |
| App | <http://localhost:3000> |
| Rails health | <http://localhost:3001/api/v1/health> |
| Kotlin health | <http://localhost:8080/actuator/health> |
| PostgreSQL | `localhost:5432` |

Open the app and select a fictional organization and identity. The local demo session is HTTP-only and Rails disables demo authentication in production mode.

Stop the stack with `docker compose down`. The PostgreSQL volume persists unless explicitly removed.

## Load the complete demo

The organization fixtures are seeded above. Usage and execution telemetry are separate, reproducible imports so their provenance remains clear.

```bash
# Generate and import canonical synthetic usage.
demo/generators/generate-usage.sh 2026-11-10 2026-12-10 42
docker compose exec usage-engine bin/usage import /app/demo/fixtures/usage-events-v1.csv --source demo-synthetic-v1

# Load pricing, post priced usage through the durable outbox, then reconcile.
docker compose exec core-api env MONTHS=2026-11,2026-12 bin/rails finance:demo_setup
docker compose exec usage-engine bin/usage load-prices
docker compose exec usage-engine bin/usage price --source demo-synthetic-v1
docker compose exec usage-engine bin/usage deliver --limit 10000 --workers 4
docker compose exec usage-engine bin/usage reconcile --source demo-synthetic-v1

# Generate execution records from actual imported run IDs and import them.
demo/generators/generate-agent-executions.sh 42 demo-synthetic-v1
docker compose exec usage-engine bin/usage agent-import /app/demo/fixtures/agent-executions-v1.jsonl --source demo-synthetic-v1

# Optional: seed budget and approval examples.
docker compose exec core-api bin/rails budgets:demo_setup
docker compose exec core-api bin/rails requests:demo_setup
```

All import commands return structured JSON reports. Replaying the same input is safe: canonical usage and agent execution imports report duplicates rather than inserting new records. The execution generator references existing usage run IDs and does not mutate usage or finance.

## Demo identities and access model

The demo includes two fictional tenants:

- **Aperture Technologies** — a larger multi-team organization with cross-functional projects.
- **Northstar Labs** — a smaller organization for contrasting scopes and structures.

Try Olivia Chen (organization viewer), Marcus Rivera (team manager), Priya Shah (project lead), and Jordan Lee (employee). Their views differ because every request is evaluated by Rails `AccessPolicy`; navigation and client state are not authorities.

- Organization viewers can inspect their tenant’s organizational reporting data.
- Managers see their managed people and unit scope, not the organization by default.
- Project leads can inspect explicitly led-project activity without receiving unrelated team authority.
- Employees can view their own private usage and allowance information.
- Financial operators are explicit grants; titles, memberships, and read scope never imply financial mutation authority.

## Engineering highlights

### Correctness and auditability

- Usage identity is tenant + source + event ID; execution identity is tenant + source + run ID.
- Import replays are idempotent; conflicting payloads are rejected with durable diagnostics.
- Prices are effective-dated and monetary values use decimal strings/`BigDecimal`, never binary floating point.
- Priced usage flows through a transactional outbox and idempotent Rails financial consumer.
- Financial transactions, ledger entries, corrections, and approval decisions are append-only.
- Corrections reverse/replace expense effects without rewriting the original record.
- Reconciliation makes incomplete pricing/delivery visible instead of silently presenting estimates.

### Privacy and authorization

- Tenant filtering begins every query; out-of-scope resources resolve as not found.
- Internal service calls use independent credentials for references, finance delivery, and analytics.
- The frontend BFF only permits known API paths and forwards the opaque demo session—not service tokens.
- TanStack Query keys include organization, identity, effective access fingerprint, and resource/filter path to prevent cross-identity cache leakage.

### Data contracts

- [Usage event CSV v1](contracts/usage-event-v1.md) documents canonical event ingestion.
- [Priced usage event v1](contracts/priced-usage-event-v1.md) documents Kotlin-to-Rails financial delivery.
- [Agent execution JSONL v1](contracts/agent-execution-v1.md) documents explicit run outcomes, attempts, errors, and read-only usage linkage.

## Verification

The project includes unit, integration, request, concurrency, contract, and browser coverage.

```bash
docker compose exec frontend npm run lint
docker compose exec frontend npm run typecheck
docker compose exec frontend npm test
docker compose exec frontend npm run test:browser
docker compose exec frontend npm run test:access
docker compose exec frontend npm run test:projects
docker compose exec frontend npm run test:analytics
docker compose exec frontend npm run test:budgets
docker compose exec frontend npm run test:requests
docker compose exec frontend npm run test:agents
docker compose exec frontend npm run test:agent-insights

docker compose exec core-api bundle exec rspec

docker compose exec usage-engine ./gradlew test
docker compose exec usage-engine ./gradlew integrationTest
```

The PostgreSQL integration suite uses the isolated test database and the restricted usage role. Rails specs cover authorization, business constraints, financial integrity, and concurrency behavior. Browser tests exercise persona switching, scope boundaries, failures, responsive layouts, and direct-internal-route denial.

## Repository guide

```text
frontend/               Next.js application and browser checks
services/core-api/      Rails API, policies, finance, requests, RSpec
services/usage-engine/  Kotlin ingestion, pricing, analytics, Flyway, JUnit
contracts/              Versioned service and import contracts
demo/                   Fictional organizations, generators, and fixtures
docs/                   Architecture, development, metric definitions, verification
infra/                  PostgreSQL bootstrap and local infrastructure
```

## Project status and limits

TokenTrack is a polished local demonstration environment, not a production deployment. It intentionally excludes real provider integrations, SSO, HRIS/billing connectors, provider-side spend enforcement, multi-region infrastructure, and compliance certification. It does not claim production-scale capacity.

Productionizing it would require a real identity provider, secret management and rotation, HTTPS/hosting, observability, backup and migration operations, provider integration hardening, and an explicit compliance/security program.

## Documentation

- [Local development and troubleshooting](docs/development.md)
- [Architecture](docs/architecture.md)
- [Financial ledger](docs/financial-ledger.md)
- [Model pricing](docs/model-pricing.md)
- [Analytics contract and definitions](docs/analytics-contract.md)
- [Agent efficiency metrics](docs/agent-efficiency-metrics.md)
- [Agent optimization: comparisons, thresholds and insights](docs/agent-optimization.md)
- [Slice 9B report](docs/slice9b.md)
- [Demo guide](demo/README.md)
