# Slice 2 — implementation and verification

Implemented and verified locally on **November 7, 2026**. This is the current report; [verification.md](verification.md) preserves the Slice 1 history.

## A. Implementation summary

TokenTrack now provides an authenticated local organizational demo with backend-enforced access. Two fictional tenants support leadership, manager, project lead, and employee experiences. Profiles, reporting context, expandable organization exploration, searchable people/projects, scoped project metadata edits, persistent themes, loading/error states, and real health checks work.

The existing Next.js design tokens, Geist fonts, Lucide icons, Button/Badge/Tooltip patterns, Docker setup, and health integration were reused. No ingestion, pricing, spend analytics, financial transactions, budget accounts, approvals, provider integrations, or cloud deployment were added.

## B. Database architecture

All new tables are in Rails-owned `business`; Kotlin-owned `usage` has no domain tables.

| Entity | Purpose and relationships |
| --- | --- |
| Organization | Tenant, name/slug/description, explicit demo flag |
| OrganizationalUnit | Arbitrary-depth parent tree, tenant-bound parent, unit type |
| User | Tenant participant, extensible function/title, active status, explicit demo identity flag |
| OrganizationalMembership | Person-to-unit relationship; one primary home team, optional additional memberships |
| ReportingRelationship | Manager/report edges, distinct from projects; self/cycle/cross-tenant protection |
| Project | Tenant initiative, unique tenant slug, description, status |
| ProjectMembership | Collaboration role; owner/lead labels do not grant platform permissions |
| RoleAssignment | Explicit self/organization/unit/project grant, validated foreign-key scope |
| DemoSession | Revocable opaque-token digest, user/tenant reference, eight-hour expiry |

UUID primary keys, tenant-bound composite foreign keys, unique indexes, non-null fields, partial uniqueness, and role/scope/status checks protect the database. Hierarchy validations and PostgreSQL triggers prevent cycles, including writes bypassing model validation. Distinct subtree counts avoid double-counting a person with overlapping memberships.

Canonical SQL snapshots preserve PostgreSQL functions/checks/triggers. A small Rails task hook leaves schema creation to Docker's bootstrap role, allowing ordinary migration and snapshot-loading commands to work with the restricted application role. The isolated test database successfully loaded this snapshot.

Seeds produce Northstar Labs (10 people, 4 units, 3 projects) and Aperture Technologies (64 people, 12 units, 5 projects). Stable seed keys generate stable UUIDs; all addresses use `.example`. Repeated seeding preserves IDs/counts. Demo-only reset was tested transactionally in the isolated database and preserves non-demo tenants.

## C. Authentication and authorization

The browser sends same-origin requests to Next.js `/api/core/*`. The BFF forwards an HTTP-only cookie to Rails, never trusting identity/role headers. Rails resolves its random token through a stored SHA-256 digest and expiry, then loads the active backend user. Switching revokes the old session and rotates the token; logout and expiry invalidate access. Neither the token nor organizational data is persisted in localStorage.

Demo selection is restricted to flagged active people in flagged fictional tenants and requires enabled demo mode in development/test. Production always disables it, even when `DEMO_AUTH_ENABLED=true`. This local impersonation mechanism does not establish real-world identity and is not a production login.

`AccessPolicy` is the reusable permission boundary. It combines explicit scoped grants, tenant-filtered relations, direct/subordinate reporting context, and permitted collaboration directory metadata. Presenters enforce separate directory and self/management projections. Reporting data and private contact fields require additional authority; effective access grants belong to their owner. Project detail may expose only its relevant coordination grants. Project editing requires an explicit project-lead grant.

Cross-tenant/out-of-scope objects return 404; forbidden actions on visible resources return 403; missing sessions return 401; invalid project values return structured 422. JSON mutations require a permitted Origin in Next.js and the configured frontend Origin in Rails. All organizational responses disable HTTP caching.

## D. Frontend experience

| Persona | Seeded example | Experience |
| --- | --- | --- |
| Leadership | Olivia Chen | Organization totals, department/subtree structure, employee exploration, all tenant projects |
| Manager | Marcus Rivera | Managed team, direct reports, scoped management profiles, relevant team projects; separately leads Developer Productivity |
| Project lead | Priya Shah | Led initiatives, contributors/participating teams, project metadata editing; no contributor line-management authority |
| Employee | Jordan Lee / Sofia Patel | Own profile, manager chain, home/additional teams, assigned projects, own capabilities and restrictions |

The profile includes identity, job function, home team, project roles, focused reporting chart, and readable access information from Rails. Manager/direct-report/project links navigate to authorized details. The organization explorer has an expandable hierarchy, selected-unit details, direct and subtree counts, managers, paginated roster, children, and relevant projects. Managers' default tree is their managed subtree. Projects support status, department/subtree, membership, and name filtering; participant responses and rosters are paginated. Future financial sections remain compact placeholders.

TanStack Query caches by tenant, identity, and resource/filter path. Identity switching immediately removes privileged content, cancels in-flight queries, clears cached data, changes the backend session, and fetches new scope. Generation checks stop late responses from restoring old identities. BroadcastChannel applies the same clearing to other tabs. Project edits invalidate relevant views rather than refreshing the entire app. Initial data uses skeletons; explicit actions use compact pending states; failures have retry controls.

Light/dark themes persist independently. The active person and organization remain visible at narrow widths. Native mobile dialogs, scrollable tables, and vertically focused charts preserve usability.

## E. Executed verification

| Command or check | Actual result |
| --- | --- |
| `docker compose config --quiet` | Passed |
| `docker compose build` | All three development application images built |
| `docker compose up -d` | All four services started, PostgreSQL healthy |
| Final `docker compose up --build -d` | Exact documented startup command succeeded; application left running |
| `docker compose exec core-api bin/rails db:migrate db:seed` | Business migration applied; transactional seeds succeeded; repeated successfully |
| `docker compose exec -e RAILS_ENV=test core-api bin/rails db:migrate` | Isolated test schema loaded/migrated successfully |
| `docker compose exec core-api bundle exec rspec` | **52 examples, 0 failures** |
| `docker compose exec frontend npm run lint` | Passed with no lint warnings |
| `docker compose exec frontend npm run typecheck` | Strict TypeScript and Next.js route generation passed |
| `docker compose exec frontend npm test` | **5 health-integration tests passed** |
| `docker compose exec frontend npm audit` | **0 reported vulnerabilities** |
| `npm run build` in Node 24 container | All App Router pages and server routes built |
| Frontend and Rails production Docker targets | Both built successfully |
| `docker compose exec usage-engine gradle test --rerun-tasks` | **2 JUnit tests executed and passed**; Kotlin source unchanged |
| `npm run test:access` in Playwright container | Full four-persona suite passed |
| `npm run test:browser` in Playwright container | Preserved health/theme/navigation suite passed |
| Tablet/mobile checks | Profile chart, organization tree, and project directory at **768px and 390px**; visible context and no horizontal page overflow |
| Production Rails runtime | Health 200; `/me` 401; demo identities and session creation 404 despite enabled flag; temporary container/credential file removed |
| Final live data/health checks | Aperture 64 people, Northstar 10; zero domain tables in `usage`; both backend endpoints and Next.js aggregate returned HTTP 200 |
| Final hygiene/log checks | Local passwords absent from Git-visible files, temporary production credential file removed, `git diff --check` passed; recent logs contain no startup/runtime exceptions |

The browser access suite verifies real database-derived counts, all four experiences, server-denied management/cross-tenant requests, limited directory projections, session persistence on refresh, HTTP-only/SameSite cookies, no auth tokens in localStorage, manager report access, project-lead boundaries, project filters, permitted edits and restoration, error/retry/loading states, restricted editing UI, mobile navigation, themes, a second tenant, Origin rejection, logout, and no browser runtime exceptions.

It also cached a leadership-only employee profile in a second tab, switched to Employee in the first tab, and confirmed private fields/navigation disappeared in both tabs. Screenshots were captured outside the repository under `/private/tmp/tokentrack-slice2` and `/private/tmp/tokentrack-browser` and visually inspected.

Negative health checks temporarily stop Kotlin: the authenticated Settings UI shows Usage Engine disconnected, Core API connected, and database connectivity unconfirmed. The service is restored afterward. Health response parsing/timeout tests and the historical real PostgreSQL outage/recovery checks remain part of the foundation.

## F. Major files

| Layer | Main changes |
| --- | --- |
| Rails data | `db/migrate/20261107000100_create_organizational_foundation.rb`, `db/structure.sql`, nine models, `TenantRecord`, `Hierarchy` |
| Rails API/security | `AccessPolicy`, `WorkspacePresenter`, versioned base/demo/me/organization/unit/user/project controllers, routes |
| Demo/tests | `lib/demo_data.rb`, `db/seeds.rb`, demo/schema tasks, model/policy/session/authorization specs |
| Frontend session/data | `session-provider.tsx`, `api-client.ts`, `use-workspace-query.ts`, workspace types, `/api/core/[...path]` |
| Frontend product | Role-aware shell and overview; organization/profile/project explorers; people/teams/detail routes; planned-section routes; reusable workspace UI |
| Verification | `e2e/access-control.mjs`, updated health/browser smoke script |
| Infrastructure/docs | Demo flag and frontend Origin in Compose/example env, PostgreSQL client in Rails image, README/current architecture/setup/contracts/demo documentation |

## G. Known limits and tradeoffs

- No production authentication, real identity proofing, SSO, role administration, member editing, or financial workflows. Most entity exploration is read-only; only scoped project metadata editing is implemented.
- The architecture has tenant-aware indexes, recursive hierarchy traversal, bounded lists/rosters, and eager loading. It was **not load-tested at 10,000 employees**. Some policy scopes materialize ID sets and project summaries eager-load participant context; larger datasets should be profiled before making scalability claims.
- Browser checks cover Chromium at desktop/tablet/mobile widths. Safari/Firefox, a formal accessibility audit, and multi-user load/concurrency testing were not run. Hierarchy safeguards were tested through model and direct database writes, not a concurrent-writer stress test.
- Host-native workflows and destructive Docker volume resets are documented but were not executed in Slice 2. Demo-only reset was executed only in the isolated test database. Existing local Gradle cache volumes can produce non-fatal Compose label warnings because they were created during toolchain bootstrap.
- Session/access snapshots refresh on identity restore/change; organizational resources use short-lived in-memory caching. Real production permission administration and immediate revocation UX will need a dedicated design.
- ESLint 9 remains the compatible version for the existing Next.js plugin peer ranges and emits an npm deprecation notice during install. Lint is clean and the dependency audit reports zero vulnerabilities, including the existing scoped patched-minimatch override.
- Docker Desktop stopped during final work and was restarted. Containers and PostgreSQL data recovered; final checks resumed successfully.

## H. Beginner-friendly architecture walkthrough

A job function describes what someone does, such as designer or engineer. A platform role describes authority, such as viewing an organization or managing one unit. Titles never grant permissions automatically.

Organizational membership places a person in teams; reporting relationships identify managers. Project membership connects people across those teams for collaboration. Priya can lead Jordan's project without being Jordan's reporting manager or gaining private management access.

Rails identifies the current person from the opaque session cookie, then builds policy scopes for that tenant and identity. Next.js displays the resulting capabilities/navigation, while Rails protects every API call independently. Changing a URL, organization parameter, role header, or project membership label cannot broaden access.

Switching identity changes both the backend session and frontend data boundary. Without clearing/cancelling caches, a former executive view could remain visible to an employee. Identity-specific keys, generation checks, immediate hiding, and cross-tab notifications prevent that transition leak.

Future budget approval requires a new explicit scoped permission and workflow tests; current read/project-edit roles imply no financial authority. Future Kotlin events will reference these stable organization/user IDs through validated contracts. Kotlin will process usage in `usage`; Rails will own authorization, attribution, and authoritative financial posting in `business`.

See [development.md](development.md) for exact startup/test/reset commands and [architecture.md](architecture.md) for the system diagram and policy matrix.
