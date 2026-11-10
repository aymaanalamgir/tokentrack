# Financial ledger

Rails exclusively owns `business.budget_accounts`, `budget_periods`, `priced_usage_receipts`, `financial_transactions`, and `ledger_entries`. Kotlin writes only `usage` and calls the authenticated financial contract. Neither service can write the other's schema.

## Accounts and allocation

Each tenant has USD accounts owned by its reserve, explicit unassigned bucket, organizational units, and projects. Monthly UTC periods keep funding and expense separate. Funding credits enter the reserve through an explicit, audited operation. Transfers debit one account's funding and credit another in the same tenant/month/currency. They cannot overdraw available source allocation and cannot create organizational funding. Period locks serialize competing transfers.

`funding = SUM(funding_delta)`, `expenditure = SUM(expense_delta)`, `available = funding - expenditure`. No balance column is mutated. A funded account can continue receiving actual expenses after available allocation goes negative; report `over_budget` rather than discarding incurred costs. Closed periods reject new allocation operations; explicit historical corrections preserve their original accounting period.

Charge resolution uses a funded active project account first, then a funded primary home-team account, then an explicitly funded unassigned account. A supplied project requires a recorded membership covering event time. Unknown project history is held, not silently reassigned. Home-team attribution is established only when the current primary membership's creation/update precede the event; otherwise its historical owner is unknown and an explicit unassigned bucket may be used. Reserve is never an implicit fallback. Missing eligible ownership persists an unresolved receipt with a diagnostic and HTTP 202; delivery retries after funding/reference repair. Current archive/inactive status does not erase legitimate incurred historical expense. Employee, project, home-unit and account dimensions are snapshotted for reporting; project expenditure is one charge even when grouped by employee or team.

## Posting and audit

Every priced-event receipt stores the normalized payload and SHA-256 fingerprint. Priced-event UUID and canonical usage UUID are unique. A per-usage advisory lock serializes first receipt/posting. Exact repeats return the original acknowledgement; mismatched payloads/identities return 409. Receipt posting and one original `usage_charge` transaction/expense entry commit together. Both receiver uniqueness and sender durable retries are required for at-least-once delivery without duplicate financial effects.

Transactions record source, amount, UTC period, actor/reason where applicable, dimensions and audit context. Entries carry separate signed funding/expense deltas. Deferred PostgreSQL checks validate funding shape, balanced two-leg transfers, receipt/source matching, and correction pairs. Tenant-bound foreign keys prevent foreign account/person/project references. Unique original usage charges prevent duplicated expenditure.

Ledger transactions and entries reject UPDATE, DELETE, and TRUNCATE. Entry inserts must occur in the parent's creation transaction, preventing later append-to-existing-transaction tampering. Corrections are explicit new transactions: a `reversal` contributes negative original expense; an optional `adjustment` contributes replacement expense. Both preserve the original dimensions/month and refer to the original transaction. One correction group allows exactly one reversal/replacement pair; an origin cannot be reversed twice. Stable operation keys make retries idempotent and reject changed requests. Correcting an adjustment creates a further linked audit chain. The original receipt and delivery acknowledgement still identify the original charge.

These are DML integrity protections under restricted service roles. A table owner/migration administrator can alter DDL; that administrative trust boundary is not a tamper-proof external accounting system. Real PostgreSQL tests briefly disable owner-level triggers inside rollback-safe, isolated test-tenant cleanup; no application/runtime bypass exists.

## Authority and local operations

Only an explicit organization-scoped `financial_operator` assignment authorizes funding, transfers, corrections and account reports. Leadership titles, viewer, manager, project participation and project lead permissions do not imply financial authority. Operations recheck an active actor and own-tenant authority transactionally. Local Rails rake commands are trusted developer operations that identify an authorized actor; they are not public impersonation endpoints. No browser finance route or dashboard is provided.

`finance:demo_setup` is an explicit local-demo action granting Maya/Olivia financial roles and creating deterministic accounts. Normal organizational seeds grant no financial authority. For each requested month it credits **100,000 USD per organization** and allocates 50,000 across unit accounts, 20,000 across project accounts, 20,000 unassigned and 10,000 retained reserve. This is synthetic funding, not spend or usage-derived money. Decimal allocation conserves every fractional unit. Repeating setup is idempotent. Demo reset refuses organizations with financial history; never remove append-only history to reseed.

## Reconciliation

`bin/usage reconcile` compares canonical/unpriced coverage, priced snapshots, outbox states, accepted receipts, original transaction amount, original ledger expense, fingerprint and acknowledged transaction/usage IDs. Rails reports actual descendant correction deltas separately; net expense must equal original ledger plus those entries. A mismatch cannot be disguised as an adjustment. It also detects missing posts and unresolved owners; global checks count duplicate original expenses, unbalanced transfers, malformed operation entries, and posted receipts without original charges.

Statuses: `reconciled` (exit 0); `balanced_with_unpriced_usage` or pending work (exit 2); discrepancy (exit 3). A balanced financial ledger does not mean unsupported usage has been billed. Reports expose incomplete coverage explicitly. `finance:report` provides actor-scoped monthly account funding/expenditure/available strings and over-budget flags. Currency conversion, invoices, funding approval workflows and analytics APIs remain future work.

## Slice 7 controls and interactive operations

`/budgets` now exposes authorized existing account reads, reserve funding, transfers, empty-month initialization and funding history through the existing Finance::Operations methods. Organization_budget_reader is read-only; unit/project reader grants remain scoped. Financial_operator remains required for monetary writes. No account balance column or parallel ledger was introduced.

Personal SpendingLimit revisions and project SpendingLimitAllocation snapshots are separate, non-funded controls. Creating or redistributing them never appends ledger funding or expense. Their consumption uses the employee's own corrected expense family, including the existing -0.0065 USD adjustment effect. Project-associated employee consumption remains separate from project-funded account expenditure.

Explicit capped AllowanceDelegation records allow direct-report ceiling administration without granting transfer authority. Thresholds, current remaining capacity and transparent recorded-date run-rate estimates are derived from actual records. Overages do not block ingestion or erase charges. The [budget contract](budget-allowances.md) details partition floors, eligible membership, revision/idempotency rules and database safeguards. Demo reset also refuses spending-control history.
