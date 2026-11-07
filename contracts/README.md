# Service contracts

Slice 1 exposes only health contracts:

| Endpoint | Healthy response | Unhealthy response |
| --- | --- | --- |
| Rails `GET /api/v1/health` | HTTP 200, `{"service":"core-api","status":"ok","database":"connected"}` | HTTP 503, `{"service":"core-api","status":"error","database":"disconnected"}` |
| Kotlin `GET /actuator/health` | HTTP 200, `status: UP`, `components.db.status: UP` | HTTP 503, `status: DOWN`, `components.db.status: DOWN` |
| Next.js `GET /api/health` | HTTP 200, aggregate checks with `checkedAt` | HTTP 503, individual `error`/`disconnected` results |

Next.js accepts database connectivity only from a recognized backend health response. Missing fields, invalid JSON, non-success status codes, timeouts, and network errors cannot produce a green service indicator. Database status requires confirmation from both services. If a backend is unreachable, this means its database connection **cannot be confirmed**, not that the PostgreSQL process is necessarily stopped.

Future slices will add versioned reference-data and priced-event contracts here. Kotlin will obtain valid business identifiers through those contracts and deliver priced events to Rails. Rails will authorize and post financial transactions idempotently. These contracts and operations do not exist yet.
