# Slice 7 — budget management and personal spending controls

Implemented and verified November 10, 2026 UTC, on `main` at `c8a016492d7eb2173329d39e594d0e0967e75123`. The local checkout already contained uncommitted Slice 6 implementation; that work and historical reports were preserved. Inspection focused on existing financial models/operations, reporting scopes, session/query conventions and the budget UI rather than reanalyzing the entire repository.

Open **http://localhost:3000/budgets?month=2026-11**. [Budget and allowance rules/API](budget-allowances.md) defines the contract. [Machine-readable results](verification/slice7-results.json) records actual current balances, controls and audit movements.

## A. Implementation summary

The Budgets placeholder is now an operational monthly workspace. Authorized financial operators can inspect funded accounts, initialize empty periods, record explicit reserve funding, review/confirm idempotent transfers, administer personal ceilings and grant/revoke capped direct-report authority. Employees can atomically redistribute unused personal capacity among eligible projects. Scoped managers/project leads receive distinct account/control/contributor views. Warnings, remaining capacity and recorded-date run-rate estimates use actual ledger facts.

The existing Finance::Operations implementation performs every financial funding/transfer write. Existing Kotlin ingestion, pricing, delivery and reconciliation were not redesigned or modified for Slice 7. No new usage fixture, provider API, approval inbox, notification service or cloud deployment was introduced.

## B. Financial domain changes

Funded accounts hold allocation. SpendingLimit/SpendingLimitAllocation hold controls, not money. Establishing Jordan's ceiling and moving capacity among personal projects creates only control revisions: no ledger funding, transfer, expense, or additional original charge.

Consumption follows each employee's own corrected financial expense family. A project's entire budget is never treated as one contributor's consumption. Project-associated usage, team-attributed activity and charged project/team account expense remain separate perspectives. Actual overages are retained and warned; ingestion is not blocked.

Partitions are strict: project-associated spending counts against its assigned sublimit and overall personal ceiling; unassigned spending counts against unallocated capacity. An unassigned project partition is zero capacity, not a hidden claim on another partition. Thus a user can have personal capacity remaining while an unallocated project shows an overage. Prior consumption floors protect used capacity during employee reallocation.

## C. Database design and historical records

Two additive Rails migrations create:

- SpendingLimit: unique tenant/employee/UTC month/USD parent, active/closed status and current revision pointer.
- SpendingLimitRevision: immutable ceiling, revision number, actor, kind, reason, operation key/fingerprint and creation transaction ID.
- SpendingLimitAllocation: immutable complete project partition snapshot per revision, unique project per revision.
- AllowanceDelegation: explicit manager/unit/cap/inclusive month window, grant audit and one recorded revocation.
- An explicit read-only organization_budget_reader role, leaving existing mutation authority separate.

Composite tenant FKs, finite nonnegative NUMERIC(38,15), monthly uniqueness, current-revision ownership/latest checks and deferred partition-sum constraints enforce structural integrity. New allocations must share the revision's creation transaction; committed revision/allocation updates/deletes/truncation are rejected. Parent identity/deletion/truncation is protected. Existing ledger tables/constraints were preserved.

Organization authority and employee/month locks serialize concurrent control writes; fresh actor checks and expected revision IDs prevent stale updates. Stable operation keys return identical existing revisions and reject changed payloads. Currently the demo has **4 monthly parents, 14 immutable revisions, 44 historical partition rows, and 1 delegation**. Repeated browser actions intentionally add revisions without replacing history.

Tests with committed PostgreSQL connections verify competing ceilings, competing partition snapshots, identical concurrent replay and rejection of late child insertion into committed revisions. Test-only cleanup is isolated by tenant, guarded by Rails test environment, and flushes deferred checks before restoring owner-level triggers. No runtime bypass or development reset exists.

## D. Authorization

Financial_operator governs reserve funding, transfers, empty periods, ceiling administration and delegation. Organization/team/project budget readers receive account read only. Manager status alone grants no monetary write or ceiling change. A current delegation additionally requires the target to be the manager's direct line report with primary home in the explicitly delegated unit subtree; the ceiling cannot exceed the cap. Managers cannot use their delegation to raise their own ceiling.

Employees read/repartition themselves, cannot raise ceilings or edit coworkers, and cannot transfer funded money. Project leads can inspect authorized project account/contributor expense; they cannot see those contributors' unrelated personal ceilings. All lookups remain tenant-scoped. Demo impersonation is local-only, as in previous slices.

Observed November scope results:

| Identity | Personal-control rows readable | Funded accounts readable | Transfer authority |
| --- | ---: | ---: | --- |
| Olivia Chen | 64 | 19 | Yes |
| Marcus Rivera | 8 | 2 | No |
| Priya Shah | 1 | 2 | No |
| Jordan Lee | 1 | 0 | No |
| Sofia Patel | 1 | 0 | No |

Marcus's explicit delegation is at most **1,000 USD per direct-report monthly ceiling**, Platform Engineering subtree, November–December 2026. Revocation is retained and immediately respected by later mutations. Delegation permissions participate in identity scope fingerprints; they are not inferred from job titles.

## E. Backend workflows

**Personal allocation:** the employee submits a complete project snapshot with the current revision UUID and stable key. Rails locks authority/parent, validates current membership and unused-capacity floors, checks exact sum ≤ ceiling, appends revision/children and advances the pointer in one transaction. Both redistributed projects commit or neither does. No funded money moves.

**Ceiling administration:** an active financial operator or capped delegated manager submits an exact amount/reason/version. Existing partitions must still fit. The new ceiling revision preserves prior approved/control values; lowering a ceiling does not erase already-incurred consumption.

**Transfer:** the authenticated API calls the existing Finance::Operations#transfer. Same tenant/currency/month, distinct open accounts, positive amount and sufficient available allocation are enforced under locks. Two opposite funding legs append with actor/reason/source identity. A matching repeated key returns the same transaction; changed request data conflicts.

**Overrun/correction:** consumption is recalculated from signed ledger expense entries and descendants, so the existing 0.1065 → reversal → 0.1000 example increases remaining personal capacity by 0.0065 without rewriting original expense or price snapshots. Over-budget usage remains recorded. Unpriced/undelivered activity stays visible as unknown additional cost.

**Forecast:** known net expense through a selected recorded activity day divided by elapsed UTC calendar days, times days in the selected month. At least two observed days are required. Sparse/negative cases return explicit no-estimate states; completed months return actual net. Projection-only division rounds HALF_EVEN at 15 decimal places. The forecast cutoff does not change the full-month consumption/account totals and is not past-knowledge audit reconstruction.

## F. Frontend experience

The existing shell, Geist typography, neutral surfaces, thin borders, responsive chart and accessible dialog are reused. Finance gets monthly account allocation/expenditure/available/utilization, forecast/warning columns, paginated audit history, explicit reserve funding and reviewed transfers. Project account drill-down shows authorized project-specific contributors. New month initialization creates empty periods only.

Managers see read-authorized direct reports and ceiling actions only when delegated. Project leads see scoped project accounts and contributor expense without unrelated private ceilings. Employees see personal ceiling, corrected consumption, remaining capacity, project partitions, unallocated capacity, warnings, revision history and trends.

Allocation editing uses exact 15-place BigInt arithmetic for totals and overrun validation, with backend validation repeated. Transfer review shows source/destination/month/reason, human-readable and exact monetary amounts, busy state and disabled modal dismissal during posting. Keys survive unchanged review/back/retry cycles. The browser test deliberately lost the acknowledgement after a successful commit, returned to review and retried unchanged: history increased by **one**, not two.

TanStack keys include tenant, identity, scope fingerprint and complete month/filter path. Mutations invalidate budget/analytics/profile/project views and broadcast authorized cross-tab refreshes. Switching from finance to employee immediately removes privileged account information; no previous-identity placeholder data is retained. Employee and funding-history pagination are independent. Initial skeleton, refresh, empty-month and retry/reset states work in both themes/mobile.

Analytics receives compact single-month allowance/account context instead of duplicate charts. Funding-account and employee-associated totals remain explicitly labeled as different scopes.

## G. Actual financial reconciliation and demonstrations

No canonical usage was added or changed: **7,753 events**, checksum **`6a12d8cba38e9026692218e10a206ba5`**, identical to the pre-slice baseline. All original **7,364 financial transactions and 7,417 ledger entries** remain. Current totals are **7370 transactions and 7429 entries**, reflecting **6 new authorized transfers** with two legs each. Their combined funding delta is **0** and expense delta is **0**.

Those movements are one stable-key **3,000 USD Engineering → Fraud Detection** demonstration, one **3,988.052161257894736 USD December Fraud Detection → reserve** small-allocation scenario, and four separate **3 USD** reviewed browser actions from successful test iterations. Replaying the stable 3,000 key did not create another transfer; the lost-acknowledgement UI retry also produced only one effect. Distinct confirmed browser actions intentionally retain separate audit records.

Current full-month ledger-derived balances:

| Organization | Month | Funding USD | Net expense USD | Available USD |
| --- | --- | ---: | ---: | ---: |
| Aperture Technologies | 2026-11 | 100000 | 273.70690941 | 99726.29309059 |
| Aperture Technologies | 2026-12 | 100000 | 150.20875987 | 99849.79124013 |
| Northstar Labs | 2026-11 | 100000 | 49.52317072 | 99950.47682928 |
| Northstar Labs | 2026-12 | 100000 | 27.350370275 | 99972.649629725 |

Combined two-tenant/two-month verification funding remains **400,000 USD**, net expense **500.789210275 USD**, available **399,499.210789725 USD**. These combined figures are verification aggregates, not a new cross-tenant public endpoint.

Jordan's November ceiling is **500 USD**, consumption **8.8430841**, remaining **491.1569159**. The browser changed initial 250/150 partitions to **240/160**, still 400 allocated and 100 unallocated. His unassigned consumption is **1.672236245 USD**. Other project activity without a partition explicitly shows zero control capacity and its resulting overage:

| Project | Sublimit USD | Own net consumption USD | Remaining USD | State |
| --- | ---: | ---: | ---: | --- |
| AI Sales Assistant | 0 | 1.10365716 | -1.10365716 | over_budget |
| Customer Analytics | 0 | 1.47225705 | -1.47225705 | over_budget |
| Developer Productivity | 160 | 0.84256064 | 159.15743936 | within_limit |
| Fraud Detection Platform | 240 | 2.190386585 | 237.809613415 | within_limit |
| Internal Knowledge Automation | 0 | 1.56198642 | -1.56198642 | over_budget |

Sofia's explicitly labeled small **0.05 USD** ceiling has **0.57017892 USD** real November consumption and **-0.52017892 USD** remaining. No fictional 275 USD expense was generated to create an overage demonstration.

The December Fraud Detection scenario retains **11.947838742105264 USD** funding against **11.350446805 USD** actual net expense, leaving **0.597391937105264 USD** and approximately **95% utilization**. Through **2026-12-09**, the transparent linear estimate is **39.095983439444444 USD**, with projected overage **27.14814469733918 USD**. Incomplete-coverage warnings are visible; this is not a provider invoice or sophisticated prediction.

Financial reconciliation is **balanced_with_unpriced_usage** (exit 2 solely for the 448 deliberately unpriced events): 7,305 priced/delivered/posted events; zero pending/dead/unresolved owners; zero missing posts/outbox, amount discrepancies, payload conflicts, duplicate expenses or unbalanced transfers. Original modeled charges remain **500.795710275 USD**, signed correction effect **-0.0065 USD**, net **500.789210275 USD**. Service schema isolation remains unchanged: Rails cannot SELECT canonical usage; Kotlin cannot SELECT spending controls.

## H. Executed tests and checks

| Executed check | Actual result |
| --- | --- |
| Rails development/test migrations | Additive control and reader-role migrations applied |
| `bin/rails zeitwerk:check` | All is good |
| `bundle exec rspec` | **143 examples, zero failures** |
| Kotlin `gradle test integrationTest --rerun-tasks` | **86 freshly executed tests: 49 unit + 37 PostgreSQL, zero failures** |
| Frontend `npm run lint` | Passed |
| Frontend `npm run typecheck` | Passed |
| Frontend `npm test` | **11 passed** |
| `test:budgets` | Personal redistribution, invalid sums, no money creation, capped authority/privacy, stable 3,000 replay, reviewed UI transfer, committed-post acknowledgement loss, warning/forecast, themes/mobile/loading/error passed |
| Existing `test:analytics`, `test:browser`, `test:access`, `test:projects` | All passed, no runtime exceptions |
| Rails/Next.js production images | Built successfully |
| Rails/Kotlin/frontend health | HTTP 200, databases connected/UP |
| Financial reconciliation | Zero discrepancies, unchanged 448 unpriced coverage |
| Database baseline/privilege checks | Original history/checksum preserved; new transfer funding/expense net zero; foreign-schema reads denied |
| Changed-file/secrets review | No configured secret values in changed files; ignored .env retained |

Backend tests cover finite decimals, monthly uniqueness, atomic/duplicate/foreign/ineligible allocations, consumed-capacity floors, corrected personal cost, explicit/capped/revoked delegation, employee/project/tenant denial, read-only leadership, transfer conservation/idempotency, reserve funding, empty periods, independent pagination and raw SQL immutability/sum checks. Concurrency uses real committed PostgreSQL transactions, not H2 or mirrored implementation-only tests.

## I. Files modified

- Rails: four control models, two additive migrations/SQL schema snapshot, budget controller/routes, control/consumption/operations/report services, threshold initializer, AccessPolicy extensions, demo/reset integration and targeted tests.
- Frontend: functional Budgets page/workspace, exact decimal and random operation-key utilities, scoped mutation invalidation, shared chart reuse, contextual analytics budget summary, exact BFF route/filter allowlist, navigation status and browser/unit tests.
- Configuration/docs: centralized threshold environment forwarding, README/architecture/development/ledger/contracts/demo guides, budget contract, this report and machine-readable results.
- Kotlin: **no Slice 7 ingestion/pricing/ledger changes**; existing suites were re-executed. Original fixtures and historical Slice 1–6 reports remain unchanged. Existing uncommitted Slice 6 source was preserved.

## J. Known limitations

Controls monitor known posted expense and warn; they do not enforce provider-side call blocking. Unpriced/undelivered activity can understate consumption and forecasts. Account forecasts conservatively flag coverage uncertainty because charge ownership is not known for unpriced events.

Project partitions use current eligibility for discretionary changes and retain prior revisions after removal. Current home-team attribution limitations remain from previous slices. Ceiling reductions cannot silently force employee partitions below their totals; revision/repartition is required first. Full point-in-time reconstruction of past warning states is not implemented.

Funding/controls are USD-only and calendar-month based. No automatic rollover, recurring funding, fixed subscription costs, tax/invoice integration or new provider connection exists. Trusted migration/database owners can alter DDL. Production identity/financial administration and production-scale load are not proven by this local demo. New account lifecycle administration remains separate from existing demo account setup and empty-period initialization.

Funding requests, delegated approval chains, escalation, approval inboxes and notifications are deliberately deferred. No cloud, Kafka, Redis or replacement ledger was added.

## K. Slice 8 readiness

Immutable ceiling/partition revisions, expected-version writes, explicit capped manager authority, role-scoped account summaries, warnings/estimates and auditable idempotent financial operations provide the basis for personal allowance increases, project/team funding requests, delegated approval policies and decisions. A future approved action can invoke these existing operations with stable request identity; allowances still must not create funded money. Add request/decision states, routing and escalation next without changing canonical usage, price history or ledger semantics.

Reproduce through [development instructions](development.md#slice-7-budgets-and-allowances). Preserve the persistent data and audit history rather than resetting to repeat the walkthrough.
