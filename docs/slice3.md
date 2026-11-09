# Slice 3 — Project management and cross-functional collaboration

Implemented and verified locally on 2026-11-09, extending the reviewed Slice 2 commit `07f9d8cc1fd84c5e4f94db046af05a6d5f212c9f` (`user db`). The starting branch was `main` with a clean working tree. Existing models, policies, presenters, seeds, proxy, frontend explorers, and architecture were inspected before changes. The baseline Rails suite passed all 52 examples. Historical [Slice 2](slice2.md) and [Slice 1](verification.md) reports are retained unchanged.

## A. Summary

Slice 2 already provided projects, scoped directories/details, contributor viewing, metadata editing, authenticated demo identities, and organization/reporting explorers. Slice 3 extends those features with:

- Explicitly authorized project creation, optional initial administrator, and server-derived tenant/creator.
- Planned/active lifecycle, archive/restore, stable project UUIDs, and no normal project-delete operation.
- Contributor search/assignment, collaboration role changes, reversible removal, membership periods, and rejoining.
- Atomic ownership transfer, immediate backend grant revocation, and last-administrator protection.
- Primary-home-team summaries with paginated contributors loaded on expansion.
- Updated employee project profiles and authorized manager roster project links.
- Permission-driven dialogs, validation, pending/success feedback, identity-aware invalidation, and cross-tab access refresh.

No usage, pricing, financial, approval, task-board, messaging, or Kotlin business feature was introduced. The `usage` schema remains without domain tables.

## B. Backend architecture

`Project` keeps its existing UUID, organization, slug, name, description, and status. `created_by_id` records attribution for newly created projects; an unknown legacy creator may remain null. `archived_from_status` records the prior planned/active state for the Restore action.

`ProjectMembership` describes collaboration, independently of employment and reporting. Roles remain `owner`, `lead`, `contributor`, and `reviewer`. An active period has `joined_at` and null `left_at`; removal closes it. Rejoining creates a new row/UUID, preserving the earlier period. Changing the role updates the current period; there is no separate role-change audit log.

`RoleAssignment` remains the explicit permission source. `project_creator` has organization scope; `project_lead` has project scope. Membership labels never produce grants. In this slice a project_lead grant bundles metadata, staffing, transfer, and lifecycle authority on that project; these are exposed as distinct capabilities/action flags, not separately configurable grant types.

`AccessPolicy` combines explicit grants with existing read relationships. Leadership's viewer grant allows organization-wide reading without staffing/editing rights. Team managers can inspect their reports' assignments without administering those projects. A lead sees contributor directory fields, not private contact/reporting data, unless another independent management grant permits it. An organization creation grant adds creation authority without organization-wide employee read authority.

`ProjectManagement` performs focused multi-record writes. Existing-project operations lock the project row and resolve a fresh actor/policy inside the transaction. Concurrent ownership transfers therefore serialize; a queued old administrator is denied after the first transfer revokes their grant. The database verifies the completed transaction as well.

Creation explicitly creates an owner membership and project_lead grant. With no selected lead, these go to the creator. With a different lead, the chosen person receives administration and the creator receives a reviewer membership. Current local administrators must be active selectable demo identities so someone can enter the app to administer the project; ordinary contributors can be any active same-tenant employee. This picker restriction should be replaced by real authenticated identities when production authentication is introduced.

## C. API contracts

Browser requests use the existing same-origin `/api/core/*` proxy. Rails owns `/api/v1/*`. Protected responses retain `{ "data": ... }`, optional `{ "meta": { "total", "limit", "offset" } }`, and `{ "error": { "code", "message" } }` errors. HTTP caching is disabled. Mutations require the authenticated HTTP-only cookie and allowed JSON Origin at both BFF and Rails boundaries.

| Method and Rails path | Purpose |
| --- | --- |
| `GET /api/v1/projects` | Existing authorized search/status/department/membership filters and pagination |
| `POST /api/v1/projects` | Organization-scoped creation; HTTP 201 |
| `GET /api/v1/projects/eligible-users` | Initial administrator directory search for creators |
| `GET /api/v1/projects/:id` | Authorized project details, current action flags, active contributor page |
| `PATCH /api/v1/projects/:id` | Metadata and lifecycle, including archive/restore |
| `GET /api/v1/projects/:id/eligible-users` | Eligible contributor search; selectable administrators with `include_members=true` |
| `GET /api/v1/projects/:id/team-groups` | Counts grouped by primary home team, including unassigned |
| `GET /api/v1/projects/:id/memberships` | Paginated/searchable current periods; administrator-only past/all periods |
| `POST /api/v1/projects/:id/memberships` | Assign contributor; HTTP 201 |
| `PATCH /api/v1/projects/:id/memberships/:membership_id` | Update collaboration role |
| `DELETE /api/v1/projects/:id/memberships/:membership_id` | Close membership period and revoke that person's project grants |
| `POST /api/v1/projects/:id/transfer-ownership` | Atomically replace project administration |

Creation request:

```json
{"project":{"name":"Risk Research","slug":"risk-research","description":"Engineering and Product investigation","status":"planned","initial_lead_id":"SAME-TENANT-SELECTABLE-USER-UUID"}}
```

Slug and initial lead are optional. A blank slug derives from name; duplicate derived or supplied slugs return 422. Names can repeat with distinct slugs. Organization and creator fields supplied by a caller are ignored; the authenticated actor supplies both.

Assignment, role editing, transfer, and archive bodies, respectively:

```json
{"membership":{"user_id":"SAME-TENANT-USER-UUID","project_role":"contributor"}}
```

```json
{"membership":{"project_role":"reviewer"}}
```

```json
{"user_id":"NEW-ADMINISTRATOR-UUID"}
```

```json
{"project":{"status":"archived"}}
```

A project response retains existing fields and adds this structure (partial example):

```json
{"data":{"id":"PROJECT-UUID","name":"Risk Research","slug":"risk-research","status":"active","created_by_id":"CREATOR-UUID","contributor_count":3,"administrators":[{"id":"ADMIN-UUID","name":"Priya Shah","job_title":"Product Manager","can_view":true}],"permissions":{"edit":true,"members_manage":true,"ownership_transfer":true,"lifecycle_manage":true,"history":true},"available_statuses":["planned","archived"],"restore_status":"active"}}
```

Membership items include `id`, directory-only `user`, `project_role`, `joined_at`, `left_at`, `status`, `administrator`, `can_update`, and `can_remove`. Administrator is current authority, not a history of grants. DELETE uses JSON `{}` and returns `{ "data": { "id": "MEMBERSHIP-UUID", "left_at": "timestamp", "removed": true } }`.

Membership filters: `q` searches name/function; `team` is a primary home unit UUID or `unassigned`; `state` is `active` (default), `past`, or `all`. Pagination accepts `limit` 1–100 and bounded `offset`. Candidate search uses `q`, `limit`, and `offset`; the UI shows ten results and asks the user to refine search. Main member pages contain twenty rows; expanded team pages contain ten.

Missing sessions return 401; foreign/out-of-scope IDs 404; forbidden actions on readable projects 403; validation/duplicate membership/last administrator failures 422; missing required parameters 400. A stale former administrator's next mutation fails server-side regardless of cached UI state. See [full service contracts](../contracts/README.md) for DTO examples and filter details.

## D. Frontend experience

The existing application shell, fonts, theme system, navigation, and table style are preserved. The project directory retains search, status, department, membership filtering, and pagination; creation appears only with the backend creation capability. Project rows show leads, contributor counts, and teams.

Create/edit uses compact native modal dialogs with labeled fields, browser validation, server errors, Escape/focus handling, disabled submissions, and inline pending feedback. Creation navigates using Next.js routing without a document reload. Successful writes produce a dismissible status message.

Project detail distinguishes authorized administration from owner/lead collaboration labels. It includes lifecycle controls, metadata editing, grouped primary-team relationships, a searchable member table, and action dialogs. Significant transfer/removal/lifecycle changes require confirmation. The last authorized administrator has no remove action. Archived projects retain readable memberships/history but no metadata, staffing, role, or transfer controls until restored.

Team groups show summaries first. Expanding a group fetches its member page and shows collaboration role, administrator badge, and permitted profile links. This is a collaboration view, not a reporting chart. Employee profiles show authorized project role/status/leads/teams; management rosters link active projects without granting mutation authority.

Queries are keyed by organization, user, and resource/filter path. Successful writes refresh access, then invalidate project, profile, unit, organization-summary, and overview queries for that identity; only active views refetch. A project BroadcastChannel updates other same-origin tabs. A server-derived scope fingerprint detects changed grants/visibility; reduced scope hides old content and clears the private cache before rendering again. Identity switching preserves the existing cancel/clear/generation safeguards.

Active project detail/member/team views refresh every ten seconds. Visible sessions check access every fifteen seconds and on focus. This is polling and cross-tab notification, not cross-browser push: another browser discovers revocation on its next request, focus, or poll. Rails enforces revocation immediately on subsequent requests.

## E. Data integrity and migration

Migration `20261109000100_extend_project_management.rb` extends existing tables in `business` and updates `db/structure.sql` through Rails' existing SQL snapshot workflow:

- Tenant-bound creator foreign key and index; nullable for legacy provenance.
- `archived_from_status` constrained to planned/active when present.
- Membership joined/left timestamps, joined values backfilled from existing creation timestamps, and a chronological-period check.
- Replacement of all-time project/person uniqueness with a unique index where `left_at IS NULL`.
- Explicit organization-scoped project_creator role allowed by the existing role/scope check.
- Missing active membership rows for preexisting project administrators backfilled without replacing projects, users, or existing memberships.
- Deferred PostgreSQL constraint triggers require at least one active authorized administrator and require every project_lead grant to correspond to active participation by an active user.

Tenant-bound foreign keys, project/status checks, and membership-role checks continue to enforce integrity even when Rails validations are bypassed. Last-administrator guards cover direct database changes as well as application writes. Triggers check final transaction state, allowing temporary intermediate states during creation/transfer. Existing-project services lock the project before writing; direct external SQL writers must also follow transaction/lock discipline.

Planned ↔ active is allowed; either can archive; archived can restore to planned or active. Restore uses the prior state (active fallback for legacy records). No membership IDs or grant rows are discarded merely because the project is archived. Removal sets `left_at` and revokes project grants; rejoining creates a distinct period.

Transfer explicitly creates/updates the target owner membership, downgrades all former owner/lead collaboration labels to contributor, deletes all previous project_lead grants, and creates the target's grant atomically. Former contributors remain participants unless separately removed. Creator attribution remains unchanged.

Migration rollback is intentionally irreversible: multiple historical periods cannot safely fit the old all-time unique index without reconciliation. No database/volume reset was used for the upgrade. New raw projects without administrators fail the deferred constraint; seed/service creation must include membership and grant in the same transaction.

Seeds retain deterministic UUIDs and extend both existing organizations. Maya and Olivia receive explicit creation grants, and Priya receives delegated creation. Jordan remains in Platform Engineering while contributing to Fraud Detection and Developer Productivity; Fraud Detection includes Engineering, Product, Design, and Data/AI. Seed reruns restore declared fixture memberships and administration without duplication. They intentionally restore stable fixture periods, while ordinary application rejoining creates new periods. User-created projects/history are retained until a deliberate demo reset.

## F. Tests and verification

Executed locally against Docker Compose on 2026-11-09; details below record observed results, not planned checks.

| Command/check | Observed result |
| --- | --- |
| Baseline `docker compose exec -T core-api bundle exec rspec` | 52 examples, zero failures |
| Development/test `bin/rails db:migrate`, development `db:seed` reruns | Applied without replacing fixture IDs; repeatable seeds |
| Final Rails `bundle exec rspec` | 70 examples, zero failures, including real concurrent transfer |
| Frontend `npm run lint` | Passed |
| Frontend `npm run typecheck` | Passed |
| Frontend `npm test` | Five tests passed |
| Kotlin `gradle test --rerun-tasks` | Two tests passed, zero failures/errors; BUILD SUCCESSFUL |
| Chromium `npm run test:projects` | Full creation/staffing/history/transfer/archive/restore and responsive workflow passed |
| Chromium `npm run test:access` | Existing four-persona, tenant, edit, cache, theme/loading/error regression passed |
| Chromium `npm run test:browser` | Real-health, desktop/mobile, persisted theme, navigation, and 404 recovery passed |
| `docker compose up --build -d` and `docker compose config --quiet` | Four services running; valid Compose configuration |
| Production frontend and Rails Docker stages | Built successfully; no deployment |
| Live Rails/Kotlin/Next.js health | All HTTP 200; both database connections confirmed |
| Seed ID/count snapshot before and after two reruns | Identical across all eight business domain models; 74 people, 16 units |
| Schema ownership inspection | business owned by core role; usage owned by usage role; zero usage domain tables |
| Recent application logs and `git diff --check` | No server exceptions/500 responses or whitespace errors found |

The new Rails request suite covers explicit creation, invalid/foreign initial administrators, duplicate slug, delegated authority, eligible-user privacy, assignment and role validation, active uniqueness, primary-team groups, leave/rejoin/history, direct database constraint enforcement, multiple administrators, last-administrator protection, removal grant revocation, transfer, archived immutability/restore, origin/session checks, and foreign IDs. Existing Slice 2 tests remain intact.

A separate committed-connection concurrency spec runs two transfers against the same project; exactly one succeeds and the queued former actor loses authority. It deletes only its own isolated test records after finishing. Normal request/model examples use transactional rollback.

The project browser test creates a real project, verifies a held pending request disables resubmission, checks duplicate-slug errors, adds Engineering and Design contributors alongside Product, expands primary-team groups, edits roles, removes/rejoins an employee, checks distinct history IDs, populates enough members for actual pagination, verifies manager/profile updates and unchanged home/reporting, denies employee/cross-tenant mutations, transfers authority and verifies obsolete management/history controls disappear in a second open tab, and archives/restores. It checks desktop 1440px, tablet 768px, mobile 390px, light/dark themes, and browser runtime errors. Generated screenshots are written under `/tmp/tokentrack-slice3` in the browser container; bind-mount to preserve them.

Successful browser runs leave an archived `Slice 3 Collaboration ...` review project and history, return administration to Priya, and close other contributors' active periods. They do not hard-delete history or leave Jordan with new administration. Use the existing deliberate `demo:reset` only if all demo edits should be discarded. Incomplete early browser runs that stopped at a pending-button assertion were also archived with their single creator membership preserved. The local review artifacts are not committed.

Reproduce checks using [development.md](development.md). Run frontend production builds in a separate Docker stage to avoid overwriting the running development `.next` volume. Production artifacts are builds, not a deployment. No cloud deployment, destructive database reset, or live provider integration was performed.

## G. Files modified

| Area | Main changes |
| --- | --- |
| Rails models/policy/service | Project, ProjectMembership, User, RoleAssignment; AccessPolicy; new ProjectManagement service |
| Rails endpoints/presenter | ProjectsController; new ProjectMembershipsController; BaseController error mapping; WorkspacePresenter; active-only scopes in me, units, and user views |
| Database and demo | One additive migration; generated SQL snapshot; extended deterministic DemoData |
| Backend tests | New project management request coverage and concurrent-transfer model spec |
| Frontend | Extended project explorer; new project forms/workspace; manager roster links; session/query refresh; mutation/cache helpers; status notice provider; typed DTOs; narrow BFF allowlists |
| Browser coverage | New project-management workflow and npm script; existing tests retained |
| Documentation | README, architecture, development, contracts, demo guide, and this report; historical reports untouched |

## H. Architecture walkthrough

1. **Creating a project:** the browser sends a form through Next.js. Rails identifies the session, checks its organization creation grant, and saves project, membership, and explicit lead grant together. The database rejects incomplete administration. The UI refreshes relevant queries and navigates to the new UUID.
2. **Joining a project:** an authorized administrator chooses an eligible employee. Rails verifies tenant, active status, role, and uniqueness, then starts a membership period. That same User record can join many projects.
3. **Keeping reporting separate:** assignment writes only ProjectMembership. It does not change OrganizationalMembership or ReportingRelationship, so home team and manager stay intact.
4. **Owner versus manager:** owner is a collaboration responsibility. A project_lead grant authorizes project administration; a team_manager grant authorizes team/report visibility. Neither grants the other's authority implicitly.
5. **Enforcing permission:** every request begins with the tenant and AccessPolicy. Member/lifecycle writes recheck current grants after obtaining the project lock. Hidden buttons improve usability; Rails remains the enforcement boundary.
6. **Changing ownership:** Rails promotes the target membership, replaces explicit project grants, and retains former participants as contributors in one transaction. The previous administrator's next mutation is denied. Database checks prevent a project from losing its final administrator.
7. **Refreshing the screen:** successful mutations invalidate affected identity-scoped queries and refresh access. Other tabs receive a project-change notification. Scope changes clear obsolete private cache state; polling/focus catches changes from another browser.
8. **Future attribution:** a project keeps its UUID and historical membership even when archived or contributors leave. Future events can reference the project without relying on its mutable name or deleting history. Whether a past event was valid must be checked against event-time rules, not only today's active membership.

## I. Slice 4 readiness and limits

Organization, user, and project UUIDs are stable business references. Kotlin still owns only `usage` and must never write Rails' `business` records. AI model IDs and tool IDs do not exist yet; Slice 4 must establish versioned catalogs/reference contracts and decide their ownership before referencing them in events.

A future usage event can carry organization_id, user_id, optional project_id, model_id, tool_id, event time, and an idempotency key. Required future interfaces include authenticated tenant-aware reference validation, archived-project and event-time membership rules, catalog validation/effective prices, input and priced-event schemas, ingestion/deduplication, and reliable delivery/reconciliation. None is implemented by Slice 3. Financial posting, funding approval, allocation, and ledger authority remain later Rails work.

Current limits: local selectable demo authentication; bundled project administration capabilities; no grant-management UI or persistent audit of every role/ownership edit; membership-period history only; candidate picker uses search rather than browsing every result; no push transport; no enterprise load-test claim; no production deployment/authentication. Explicit multi-administrator records are supported by the model/integrity rules, but the normal ownership-transfer action intentionally replaces all prior administrators with one target.
