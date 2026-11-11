# Slice 8 — funding requests and delegated approvals

Slice 8 adds an auditable request-to-execution workflow without adding another financial engine. Open `/requests?month=2026-11` to submit and review personal allowance, project funding, and team funding requests. Approved allowance requests call `Budgets::AllowanceOperations#revise`; approved funding requests call `Finance::Operations#transfer`.

## Request model and lifecycle

`FinancialRequest` stores the immutable submitted terms, current-value snapshot, routing result, assigned reviewer, optimistic lock, and exactly one type-correct execution reference after approval. `RequestEvent` is append-only and records creation, submission, escalation, decisions, cancellation, and execution. PostgreSQL tenant-bound foreign keys, type/target checks, positive finite decimals, immutable-term triggers, append-only event triggers, and `approved_request_has_execution` prevent malformed or partially completed approval states.

The v1 workspace uses direct submission rather than editable drafts. Persistent states are `pending`, `approved`, `rejected`, and `cancelled`; escalation is an append-only routing event that keeps the request pending. Finalized requests and their financial terms cannot be edited or cancelled.

| Type | Requested amount means | Approval effect |
| --- | --- | --- |
| `personal_allowance` | Desired new total monthly ceiling | One immutable allowance revision; no ledger entry |
| `project_funding` | Additional funding | One balanced transfer into the project account |
| `team_funding` | Additional funding | One balanced transfer into the unit account |

## Routing and authority

`Requests::ApprovalRouter` resolves active, same-tenant authority from explicit grants, reporting relationships, the accounting month, and current allowance delegations. Personal requests prefer a direct manager whose active delegation covers the requested final ceiling; otherwise they route to the first deterministic non-self financial operator. Requests above a manager's cap route directly to financial authority, so increments cannot be split to bypass the final-ceiling cap.

Funding requests always require an explicit organization `financial_operator`. Project leads and team managers may request funding for their explicitly authorized scope, but those roles do not authorize transfers. Self-approval is denied. Revoked/expired delegation, inactive actors, archived targets, closed periods, foreign records, and unrelated request identifiers fail closed. Leadership read access alone confers no request decision authority.

## Atomic execution, idempotency, and concurrency

`Requests::DecisionService` locks the request and re-evaluates the current actor and target before execution. Personal approvals require the submitted allowance revision still to be current. Funding approvals revalidate the current source account, open period, and available allocation. The existing operation runs inside the request transaction; only after it succeeds are the decision, execution reference, and audit events committed.

Each command carries a stable cryptographic operation key. The business mutation also uses the stable key `request/<request-id>/approve`. An identical lost-response retry returns the recorded result; a changed or competing decision conflicts. Real PostgreSQL races verify that simultaneous identical allowance retries create one revision and competing financial operators create one transfer and one final decision.

## API v1

All endpoints require the existing backend session, same-origin JSON for mutations, tenant scope, decimal strings, bounded pagination, and server-calculated capabilities.

| Method/path | Contract |
| --- | --- |
| `GET /requests` | Authorized My Requests, Pending Review, History, creation options, filters, and pagination |
| `GET /requests/:id` | Authorized detail plus append-only activity history |
| `POST /requests` | Directly submit one type-correct request under `{request:{...}}` |
| `POST /requests/:id/approve` | Atomically execute and approve |
| `POST /requests/:id/reject` | Require a rejection reason; no financial effect |
| `POST /requests/:id/cancel` | Requester-only pending cancellation |
| `POST /requests/:id/escalate` | Delegated manager routing to financial authority |

List filters are `request_type`, `status`, `month`, `requester_id`, `project_id`, `unit_id`, `assigned_approver_id`, `limit`, and `offset`. Personal `requested_amount` is a desired total; project/team `requested_amount` is an increment. Clients never choose an approver or submit an execution reference.

## Frontend workflow

The Requests workspace provides compact My Requests, Pending Review, and History tabs; month/type/status filters; role-specific request forms; server-derived routing; exact decimal tooltips; request details; financial-impact explanations; activity history; and controlled approve/reject/cancel/escalate confirmations. Mutation keys survive unchanged retries. TanStack Query keys include tenant, identity, scope fingerprint, and filters; mutations invalidate Requests, Budgets, and Analytics and broadcast to authorized tabs. Existing identity switching still cancels and clears privileged queries before rendering the next identity.

The Budgets workspace links directly to the matching request month. Approved ceilings appear as normal allowance revisions. Approved transfers appear in existing funding history and account utilization. Request amounts are never treated as expenditure.

## Demo and observed verification

`bin/rails requests:demo_setup` is idempotent and preserves the ledger. It creates Jordan's delegated 750 USD request, a 1,500 USD escalation example, a reserve-backed 2,000 USD Fraud Detection request, Marcus's 3,000 USD Platform request, and Sofia's rejected example. An earlier Platform-backed Fraud request remains pending as the explicit insufficient-funding scenario discovered during verification; no money was fabricated or history removed.

The browser walkthrough approved Jordan's 750 USD ceiling and exactly one 2,000 USD project transfer. The current Aperture demo contains 6 requests: 2 approved, 3 pending, and 1 rejected; 6 created/submitted event pairs, 2 approval/execution pairs, and 1 rejection. Both approved records have the correct execution reference. Aperture retains 200,000 USD total funding and 423.91566928 USD net expenditure; the request transfer changed neither.

Verification completed on 2026-11-10:

- Rails: **156 examples, 0 failures**, including real PostgreSQL request races and raw-SQL integrity checks.
- Kotlin: **86 tests**, Gradle `test integrationTest --rerun-tasks` successful; no Slice 8 Kotlin code changes.
- Frontend: ESLint and TypeScript passed; **11 unit tests** passed.
- Browser: smoke, access, project management, analytics, budgets, and requests suites passed in dark/light and desktop/mobile modes.
- Production: Core API and frontend production images built successfully.
- Reconciliation: `balanced_with_unpriced_usage`; 7,305 priced/posted, no pending/dead/missing/conflicting deliveries, no amount discrepancies, and all four ledger-integrity counters zero. The existing 448 explicitly unpriced events remain unchanged.

[Machine-readable verification](verification/slice8-results.json) records the final counts.

## Known limitations and next-slice readiness

V1 has direct submission, one deterministic assignee, one explicit escalation step, and financial-operator-only funding approval. It does not include editable drafts, arbitrary multi-stage workflow builders, funding-approval delegation, notifications, provider enforcement, or production identity proofing. List sections share one bounded offset. These constraints keep the current policy explainable.

The immutable request intent, route, decision actors, comments, execution references, allowance revisions, and balanced transfers are now available for later efficiency/optimization analysis without interpreting requested money as usage expense or rewriting financial history.
