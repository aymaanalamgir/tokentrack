# Service contracts

The Slice 1 health contracts remain unchanged:

| Endpoint | Healthy response | Unhealthy response |
| --- | --- | --- |
| Rails `GET /api/v1/health` | HTTP 200, `{"service":"core-api","status":"ok","database":"connected"}` | HTTP 503, `{"service":"core-api","status":"error","database":"disconnected"}` |
| Kotlin `GET /actuator/health` | HTTP 200, `status: UP`, `components.db.status: UP` | HTTP 503, `status: DOWN`, `components.db.status: DOWN` |
| Next.js `GET /api/health` | HTTP 200, aggregate checks with `checkedAt` | HTTP 503, individual `error`/`disconnected` results |

Next.js accepts database connectivity only from a recognized backend health response. Missing fields, invalid JSON, non-success status codes, timeouts, and network errors cannot produce a green service indicator. Database status requires confirmation from both services. If a backend is unreachable, this means its database connection **cannot be confirmed**, not that the PostgreSQL process is necessarily stopped.

Future slices will add versioned reference-data and priced-event contracts here. Kotlin will obtain valid business identifiers through those contracts and deliver priced events to Rails. Rails will authorize and post financial transactions idempotently. These contracts and operations do not exist yet.

## Slice 2 organizational API

Browsers call Next.js `/api/core/*`; Rails owns `/api/v1/*`. Except for health and explicitly enabled fictional demo entry, endpoints require the backend session cookie. Responses use `{ "data": ... }` and optional `{ "meta": { "total": 64, "limit": 25, "offset": 0 } }`. Errors use `{ "error": { "code", "message" } }`. Organizational responses have `Cache-Control: no-store, private`.

| Method/path under `/api/v1` | Behavior |
| --- | --- |
| `GET demo/identities` | Active flagged fictional choices, without private fields |
| `POST demo/sessions` | `{ "user_id": "UUID" }`; validates choice, rotates session, HTTP 201 |
| `DELETE demo/session` | Revokes session and cookie; JSON `{}` body |
| `GET me`, `me/access`, `me/overview` | Backend identity, effective scope/navigation, database-derived overview |
| `GET organizations/:id` | Current tenant summary and authorized counts |
| `GET organizational-units`, `organizational-units/:id` | Authorized hierarchy, filtered/paginated roster, children, relevant projects |
| `GET users`, `users/:id` | Authorized directory or self/management profile |
| `GET users/:id/reporting-context` | Authorized ancestry and direct reports |
| `GET projects`, `projects/:id` | Authorized projects, participants, teams, coordination grants |
| `PATCH projects/:id` | Explicit project lead only; `{ "project": { "name": "Example", "description": "Example description", "status": "active" } }` |

Lists accept `limit` (1–100) and `offset`. People/projects support `q` name search. Projects support `status`, `department` (visible unit UUID and subtree), and `membership=mine|led`. Unit lists accept `managed=true` to narrow to managed units. Unit and project details paginate members with `members_meta`, retaining the total member/contributor count. `view=management` requests stricter user-profile authority and cannot broaden scope.

Missing sessions return 401. Cross-tenant/out-of-scope lookups return 404. Disallowed actions on visible resources return 403. Invalid project fields return 422. JSON mutations require the configured frontend Origin, checked by both BFF and Rails. Demo entry is unavailable outside development/test or with `DEMO_AUTH_ENABLED=false`.

Organizational/project membership and current read/edit grants do not imply future financial approval permission.

## Slice 3 project management API

The authentication, tenant scope, no-store responses, Origin checks, pagination, and error envelope above also apply to these endpoints. The Next.js proxy permits only the listed route/method combinations.

| Method/path under `/api/v1` | Contract |
| --- | --- |
| `POST projects` | Explicit organization `project_creator`; returns project, HTTP 201 |
| `GET projects/eligible-users` | Creator-only initial-lead picker; active selectable same-tenant identities, directory fields only |
| `GET projects/:id/eligible-users` | Project administrator; active same-tenant candidates, excluding current members by default |
| `GET projects/:id/team-groups` | Authorized reader; primary-home-team counts, no unbounded contributor list |
| `GET projects/:id/memberships` | Authorized reader; active periods; `state=past|all` requires explicit administrator |
| `POST projects/:id/memberships` | Administrator; create active period, HTTP 201 |
| `PATCH projects/:id/memberships/:membership_id` | Administrator; change collaboration label only |
| `DELETE projects/:id/memberships/:membership_id` | Administrator; close period, revoke project grants, retain history, HTTP 200 |
| `POST projects/:id/transfer-ownership` | Administrator; atomically replace all project administration with target |
| `PATCH projects/:id` | Administrator; metadata while unarchived; lifecycle including restore |

Create (organization and creator are always resolved from the authenticated session):

```json
{"project":{"name":"Risk Research","description":"Cross-functional investigation","status":"planned","slug":"risk-research","initial_lead_id":"SAME-TENANT-SELECTABLE-USER-UUID"}}
```

`slug` and `initial_lead_id` are optional; slug defaults from name, and lead defaults to the actor. Slugs are unique per tenant, names need not be if a distinct slug is provided. New projects start planned or active. Initial/transfer administrators must be active selectable identities in this local demo; contributor selection allows any active same-tenant employee. `include_members=true` on the project candidate endpoint returns selectable administrator candidates including existing members. Candidate search supports `q`, `limit`, and `offset` without exposing emails, reporting edges, or private grants.

Assignment and role update:

```json
{"membership":{"user_id":"SAME-TENANT-USER-UUID","project_role":"contributor"}}
```

```json
{"membership":{"project_role":"reviewer"}}
```

Allowed labels are owner, lead, contributor, reviewer. Labels grant no system authority. Membership lists accept `q` (name/function), `team` (primary home unit UUID or `unassigned`), `state=active|past|all`, `limit` (1–100), and `offset`. A membership response has this shape (UUID strings abbreviated):

```json
{"data":[{"id":"MEMBERSHIP-UUID","user":{"id":"USER-UUID","name":"Jordan Lee","job_title":"Software Engineer","job_function":"engineering","visibility":"directory","can_view":true,"primary_team":{"id":"UNIT-UUID","name":"Platform Engineering","unit_type":"team","parent_unit_id":"PARENT-UUID"}},"project_role":"contributor","joined_at":"2026-11-09T16:00:00.000Z","left_at":null,"status":"active","administrator":false,"can_update":true,"can_remove":true}],"meta":{"total":1,"limit":20,"offset":0}}
```

A removed period has `left_at`, `status=past`, and no mutation actions. Its `administrator` flag reflects current authority, not a historical grant audit. A rejoining person receives a new membership UUID; only one period can be active. Role edits within a period are not separately audited. DELETE expects the same-origin JSON request with `{}` and returns `{ "data": { "id": "MEMBERSHIP-UUID", "left_at": "timestamp", "removed": true } }`. Removing the final authorized administrator returns 422 without changing anything.

Transfer body:

```json
{"user_id":"NEW-ADMINISTRATOR-UUID"}
```

Transfer retains former members, changes former owner/lead labels to contributor, explicitly grants the target, and revokes all previous project_lead grants in one transaction. It returns the project using the caller's **new** permissions. Subsequent requests with old authority fail immediately.

Lifecycle uses the existing PATCH endpoint:

```json
{"project":{"status":"archived"}}
```

Planned ↔ active; either → archived; archived → planned or active. Restore UI uses `restore_status` (last unarchived state, legacy fallback active). Archived projects retain IDs and membership periods; staffing, role editing, transfer, and metadata updates are denied until restoration. No project-delete API exists.

Project responses extend the Slice 2 fields with `created_by_id` (null for unknown legacy creators), `administrators`, `permissions` (`edit`, `members_manage`, `ownership_transfer`, `lifecycle_manage`, `history`), `available_statuses`, and `restore_status`. `leads` means owner/lead collaboration labels; `administrators` means actual explicit grants. `/me/access` capabilities summarize granted operations; per-project flags remain authoritative for rendering actions. `/me` and `/me/access` include `scope_key`, a fingerprint used to clear obsolete client caches when effective grants/visibility change.

Validation conflicts/invalid lifecycle/last administrator return 422, missing required parameters 400, absent authentication 401, forbidden visible actions 403, and foreign/out-of-scope users/projects/membership IDs 404. Existing resource authorization is applied before member lookup. A `Lead` label never grants access to private management projections or reporting context.
