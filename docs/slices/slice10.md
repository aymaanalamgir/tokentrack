# Slice 10 — Final integration and reliability

Slice 10 adds no product features. It ran the whole application, fixed what verification exposed, and made the demo reproducible from an empty database. Measured results are in [verification/final-results.md](../verification/final-results.md); the tour is in [demo-walkthrough.md](../demo-walkthrough.md).

## What was added

- `scripts/setup-demo.sh`: one idempotent command that loads the complete demo by orchestrating the existing setup commands in dependency order (migrations, seeds, funding, pricing, three usage sources, delivery, agent executions, spending controls, requests, the documented agent correction, reconciliation). It stops at the first failing step with that step's output, never resets or regenerates data, and fails if reconciliation reports anything other than `reconciled` or `balanced_with_unpriced_usage`.
- `scripts/verify.sh`: runs lint, typecheck, unit, Rails, Kotlin unit and integration, and the eight browser suites, with the browser suites in the pinned Playwright image and in a safe order.

## Issues found and fixed

| Issue | Kind | Fix |
| --- | --- | --- |
| Seeded project and home-team memberships took their start time from the wall clock. Usage validation and charge attribution require a membership that existed at each event's time, and the demo simulates 2026-11-10 onward, so a database seeded after that date would reject or re-attribute the checked-in events. The existing database only worked because it was seeded on 2026-11-07. | Product defect (fresh install) | New fixture memberships start at a fixed fictional epoch, 2026-11-07 UTC (`DemoData::FIXTURE_EPOCH`). Existing rows are never changed. Covered by a spec. |
| Loading the demo took about twenty manual commands spread over several documents. | Onboarding | `scripts/setup-demo.sh`. |
| README browser commands (`docker compose exec frontend npm run test:…`) fail in a freshly built frontend container, which has no Chromium. | Documentation | `scripts/verify.sh browser` uses the Playwright image; README updated. |
| `test:analytics` asserted the dataset's total adjustment was exactly `-0.0065`; the documented Slice 9B correction changed it. | Stale test assertion | Asserts the ledger identity (net = original + adjustments) and that corrections exist. |
| `test:budgets` required a `high_utilization` warning in December; Slice 9B scenario charges pushed that small account to `over_budget`. | Stale test assertion | Accepts either real warning state. |
| `test:budgets` typed a 600 sublimit and expected it to be invalid, which depended on sublimits left by earlier runs. | Test isolation | Types an amount above the whole ceiling. |
| On a fresh demo, running `test:budgets` before `test:requests` made the request approval fail with 409, because the budgets workflow revises the allowance the pending request was submitted against. The 409 is correct behaviour. | Test ordering | `scripts/verify.sh` runs requests before budgets; documented. |
| The sidebar labelled Requests "soon" although the workspace is implemented. | UI defect | Badge removed. |

No Kotlin source changed.

## Audit notes

- **Financial invariants.** Reconciliation reports zero duplicate expenses, unbalanced transfers, missing postings and amount discrepancies. Across the session's browser runs total funding stayed at exactly 400,000 and net expenditure did not move, while transfers and allowance revisions were appended. Repeating the setup command changed no totals on either database.
- **Authorization.** The access, analytics, budgets, requests, agents and agent-insights workflows each assert server-side denial (404 for out-of-scope people, projects and agents; 403 for an employee raising their own ceiling; cross-tenant denial; CSRF rejection) and that Kotlin internal routes return 401 directly and 404 through the proxy.
- **Cache isolation.** Analytics, budgets, requests and agents query keys include organization, user and scope fingerprint; the shared workspace hook keys on organization, user and path. Same-tab and cross-tab identity switching are asserted in the access suite.

## Known limitations

- The demo is anchored to simulated dates. Pages default to the real current month in a few places, so choose 2026-11 or 2026-12 where a month picker starts empty.
- Browser suites for projects, budgets and requests write to the database they run against: one archived review project and one 3 USD conserved transfer per run. This is append-only history and is not cleaned up.
- On the existing development database, December's Fraud Detection project account is over budget (138.75% of an 11.95 USD allocation) because Slice 9B scenario charges posted to it. A fresh install computes the small allocation after those charges and shows about 95% instead.
- `scripts/setup-demo.sh` does not replay the manual Slice 5 walkthrough correction (−0.0065), so a fresh database's net expenditure is 569.4558173 against 569.4493173 on the original.
- The Insights tab lists 63 findings for leadership because the Slice 9A dataset itself contains a late-window token spike.
- The organization analytics request is the slowest operation, about 0.5 s locally.
- Production images build but were not run; there is no deployment configuration.
