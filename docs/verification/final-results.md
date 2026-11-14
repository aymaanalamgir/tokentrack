# Final verification results (Slice 10)

Recorded on 2026-11-14 from commit `b7e9ec2` plus the Slice 10 working-tree changes, on macOS with Docker Desktop 29.9.2. Every figure below was produced in this session; none is copied from an earlier slice report.

## Runtime

| Check | Result |
| --- | --- |
| `docker compose ps` | postgres (healthy), core-api, usage-engine, frontend running |
| `GET :3000/api/health` | 200; core, usage and database all `connected` |
| `GET :3001/api/v1/health` | 200; `database: connected` |
| `GET :8080/actuator/health` | 200; `UP`, db `UP` |
| Rails migrations | all `up`, none pending |

## Demo initialization

| Environment | First run | Repeat run |
| --- | --- | --- |
| Existing development database | 20 of 20 steps ok; no row counts or totals changed | same |
| Disposable fresh Compose project (separate volumes and ports), built twice from empty | 20 of 20 steps ok; 9,377 usage events, 3,146 agent runs, 8,928 transactions, 5 requests | 20 of 20 ok; identical counts and totals |

Fresh install reconciliation: `balanced_with_unpriced_usage`, 8,869 priced and posted, 508 unpriced, net expenditure 569.4558173, all discrepancy counters 0. Expense by account purpose matched the development database (project 412.845040 vs 412.838540, unit 79.737237 in both); the 0.0065 difference is the manual Slice 5 correction that the script does not replay.

## Automated suites

Run with `./scripts/verify.sh` on the development stack after the last code change: 15 of 15 checks passed.

| Suite | Result |
| --- | --- |
| Frontend lint | clean |
| Frontend typecheck | clean |
| Frontend unit tests | 17 passed |
| Rails `zeitwerk:check` | ok |
| Rails RSpec | 174 examples, 0 failures |
| Kotlin unit tests | 64 passed |
| Kotlin PostgreSQL integration tests | 43 passed |
| Browser: smoke (`test:browser`) | passed |
| Browser: access | passed |
| Browser: projects | passed |
| Browser: analytics | passed |
| Browser: requests | passed |
| Browser: budgets | passed |
| Browser: agents | passed |
| Browser: agent insights | passed |

The eight browser suites also passed against the from-scratch environment. Three of them needed fixes first; see [slice10.md](../slice10.md#issues-found-and-fixed).

## Production builds

| Image | Result |
| --- | --- |
| `docker build --target production frontend` | built (`next build` compiled) |
| `docker build --target production services/core-api` | built |
| `docker build --target production services/usage-engine` | built |

The images were built, not run.

## Financial reconciliation (development database)

| Field | Value |
| --- | --- |
| Status | `balanced_with_unpriced_usage` |
| Priced / posted events | 8,869 / 8,869 |
| Unpriced events | 514 |
| Pending, dead, unresolved owner, missing postings | 0 |
| Amount discrepancies, duplicate expenses, unbalanced transfers | 0 |
| Posted original | 569.4628873 |
| Adjustment delta | −0.01357 |
| Net expenditure | 569.4493173 |

Incomplete pricing coverage (514 events with no supported profile) is intentional and is not a ledger discrepancy. During this session net expenditure did not change, and total funding stayed at 400,000.000 while the browser suites appended four 3 USD transfers (8,938 → 8,942 transactions) and two archived review projects.

## Performance

Leadership session (largest scope), real HTTP through the Next.js proxy, median of five warm requests on the development dataset (9,383 usage events, 8,942 transactions, 3,146 agent runs):

| Operation | Median | Payload |
| --- | --- | --- |
| Organization analytics, 40 days | 543 ms | 96 KB |
| Project analytics, one project | 122 ms | 50 KB |
| Agent overview, 40 days | 139 ms | 55 KB |
| Agent insights, default comparison | 146 ms | 357 KB |
| Agent-run drill-down | 24 ms | 5 KB |
| Budget overview, 2026-11 | 119 ms | 41 KB |
| Requests inbox, 2026-11 | 37 ms | 12 KB |
| `me/overview` | 32 ms | 21 KB |
| Page: dashboard | 174 ms | development server |
| Page: agents | 351 ms | development server |
| Page: analytics | 852 ms | development server |

Organization analytics is the slowest operation: 25 fixed queries (about 330 ms in PostgreSQL), not an N+1 pattern. The Slice 9B cohort paging is unchanged; its 6,200-run integration test and 6,000-run Rails spec are part of the suites above. These are small local measurements, not capacity claims.

## Not verified

- Production images were not started or exercised.
- Concurrency protections were verified only through the existing concurrency specs and integration tests, not by new load testing.
- No manual accessibility audit beyond what the browser suites assert.
