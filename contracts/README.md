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
