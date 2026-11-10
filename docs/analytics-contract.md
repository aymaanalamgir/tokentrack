# Analytics contract v1

## Public report

`GET /api/v1/analytics` uses the existing Rails demo session and AccessPolicy. Next.js forwards only this exact GET path via `/api/core/analytics`; it forwards no internal service token. Replies are `no-store, private`. Schema version is 1, under the existing `{data: ..., meta?: ...}` envelope.

Parameters are optional scalar strings; unknown parameters, arrays, invalid identifiers and malformed ranges return 400. Foreign or unauthorized entity filters return 404. Missing session returns 401. Usage-service failure returns 503 with a retryable explanation; Rails never substitutes estimated totals.

| Parameter | Meaning |
| --- | --- |
| start, end | Explicit ISO-8601 UTC timestamps ending Z; inclusive start, exclusive end; increasing range ≤366 days; years 2000–2099 |
| granularity | day (default), week, month |
| organization_unit_id | Authorized unit subtree, restricted to its current primary-home-team members |
| project_id | Authorized project; always intersects existing activity scope |
| user_id | Authorized employee activity; project-lead access remains project-restricted |
| provider, model, tool | Exact original usage dimensions, validated bounded identifiers |
| limit, offset | Posting-audit pagination, 1–100 (default 25), 0–100000 (default 0) |
| audit_start, audit_end | Separate posting-time audit range, same UTC/366-day rules; defaults to activity range |

No browser organization ID or arbitrary user-list filter is accepted. Without explicit dates, Rails discovers the available authorized data window through Kotlin, then uses the most recent 30 data days (or the shorter available window). The UI labels simulated dates. Last 7/30/90 presets and calendar-month presets anchor to available data rather than silently using today's real billing period. Custom date inputs show the end-exclusive convention.

## Permission rules

Activity scope is the union of: own usage; managed users under existing explicit team_manager/report scope; and usage in explicitly led projects. Organization viewers may read all activity in their own tenant. Directory visibility and ordinary project participation never grant complete private analytics. Every filter intersects this population. A contributor opened by a project lead remains restricted to led-project activity. A person holding manager and project-lead grants receives their union, not the private activity of everyone visible in the directory.

Current primary home-team membership is used for team activity grouping/filtering because canonical usage v1 contains no historical home-unit dimension. Team hierarchies use the established subtree resolver. Ledger audit retains the immutable original home-unit snapshot. Historical team employment reconstruction is unavailable; reports label current-home activity explicitly.

Budget account read access is independent: financial_operator can read all own-tenant accounts; team_budget_reader can read explicitly assigned unit accounts; project_budget_reader can read explicitly assigned project accounts. These new reader roles confer no funding, transfer, correction, employee-private-history or organization-wide activity authority. Ordinary leadership/manager/project-lead titles do not grant budget access. `analytics:demo_access` explicitly grants read-only examples to flagged local demo manager/project-lead identities; normal seeds do not infer these permissions. Production/demo-disabled environments reject that command.

## Response

`data` contains:

- `schema_version:1`, `currency:"USD"`.
- `summary`: events, priced_events, unpriced_events, input_tokens, output_tokens, cached_input_tokens, total_tokens, active_users, pricing_coverage_percent, unsupported_profiles, missing_rates, pending_delivery, unresolved_charge_owner, original_expenditure, adjustments, net_expenditure.
- `timeseries`: UTC buckets plus scoped token/coverage metrics and original/adjustment/net ledger expenditure. Empty buckets are filled; the first bucket may begin before the selected start, but its values only include events inside the range.
- `employees`, `teams`, `projects`, `models`, `tools`: bounded grouped aggregates with the same metrics and dimension keys. Model keys preserve original provider/model, pricing_provider/pricing_model and billing_basis; unpriced profile fields are null. Models include cost_share_percent. Tools include distinct active_users and attributed_projects. Employee rows include job function, current home unit and current authorized active-project count.
- `accounts`: authorized account funding, expenditure, remaining, utilization_percent and over_budget; null when funding read is unauthorized or activity-only user/model/tool/provider or combined project/team filters make account-wide allocation inapplicable. Empty authorized account sets return an empty array.
- `budget`: exact totals of the returned authorized accounts, or null. Funding/utilization use **full UTC accounting months intersecting the activity range**, not prorated daily budgets. Account expenditure may differ from activity-associated expenditure because of scope, partial dates, account ownership and fallback attribution. Account tables state this basis.
- `comparisons.week` and `.month`: current/previous complete UTC calendar boundaries, token totals/component changes, signed expense change, state, recorded_coverage and contributing employee/project/model/tool token deltas. Weekly buckets/comparisons begin Monday. Comparison anchor is no later than the available data end for overlapping ranges. Percentages are suppressed if either period lies partially/outside the recorded window. Missing previous activity never produces infinity. Negative monetary baselines use their absolute magnitude and are labeled. No-data, new-activity and partial-recorded-window states remain distinct.
- `transactions`: bounded posting-time audit rows, total/limit/offset and date_basis. Rows show original charge/reversal/adjustment IDs, employee/project/original home IDs, occurred_at, posted_at, accounting month and signed expense_delta. Funding transfers are not expenses and are excluded from this activity audit.
- `context`: authorized identity/tenant/scope fingerprint, explicit dates/granularity, available data range, authorized unit hierarchy/project/employee options, UTC/Monday conventions and metric labels. No unauthorized employee directory is exported as filter metadata.

Money and percentages are decimal strings (or null when undefined). Token sums may be decimal integer strings because PostgreSQL SUM(bigint) returns NUMERIC. Counts are integers. Frontend authoritative totals are never recomputed with JavaScript floating point. BigInt decimal formatting rounds only presentation; numeric conversions are confined to chart geometry, sorting and displayed percentages. Exact monetary strings appear in tooltips/export. Model rows containing only unpriced events display “Unpriced,” not a zero-cost estimate.

## Metric definitions and reconciliation

Financial totals come from `business.ledger_entries.expense_delta`. Roots are posted priced-event receipts/original usage charges; a recursive query includes all descendant reversals/replacements. Original expenditure sums original expense entries, adjustments sums linked correction entries, and net is their sum. Funding deltas and transfers never enter expenditure. Activity trends/filtering use original usage occurrence time; descendants preserve the original accounting assignment. Posting audit filters actual transaction creation time separately.

Tokens and coverage come from canonical `usage.usage_events` joined to immutable pricing/failure/outbox records. Cached input is a subset of input: total tokens = input + output, never input + cached + output. Priced does not mean posted. Pending delivery reports undelivered/missing outbox status; unresolved ownership comes from scoped unresolved Rails receipts. Only posted ledger expenses contribute spending. Unpriced usage stays in token metrics and has unknown monetary cost.

For a fixed population, employee, current-home-team, project-attributed, original-model/profile and tool breakdowns each reconcile independently to the same net activity total. They are overlapping perspectives and must never be added together. Project-funded/account expenditure is separately derived from account entries, not inferred from project tags. Distinct users/projects are calculated per group and must not be summed across overlapping dimensions.

## Internal usage read API

`POST /internal/v1/analytics` on Kotlin requires a **separate** `USAGE_ANALYTICS_TOKEN` bearer credential of at least 32 characters. Reference/financial tokens and browser cookies do not authenticate it. It is excluded from the Next.js allowlist. Body limit 64 KiB applies before JSON parsing, including chunked bodies. Unknown keys or invalid types return 400; invalid credential 401; oversized body 413.

Exactly these keys are required:

```json
{"organization_id":"FULL-UUID","all_users":false,"scope_users":["FULL-UUID"],"scope_projects":[],"filter_users":null,"start":"2026-11-01T00:00:00Z","end":"2026-12-01T00:00:00Z","granularity":"day","project_id":null,"user_id":null,"provider":null,"model":null,"tool":null}
```

UUID placeholders above stand for complete UUIDs. Rails supplies tenant and permission population; Kotlin does not authorize browser users. all_users means the stated tenant only. Otherwise population is scope_users OR scope_projects; filter_users and individual dimensions further intersect it. Lists contain unique UUIDs, at most 200 users/roster members and 100 projects. Range is ≤366 days. Each dimension aggregation is bounded to 200 groups; an oversized population fails rather than silently truncating or broadening it. Narrow the scope for larger organizations. No SQL expressions or unbounded arbitrary ID lists are accepted.

Response includes schema_version, available_range (UTC timestamps), totals, timeseries, employees, projects, models and tools. Queries use indexed tenant/time/user/project predicates and SQL aggregates. No financial business-schema reads or writes occur in Kotlin; no usage-schema grants are added to Rails. Each Kotlin request and Rails ledger report uses a repeatable-read snapshot; the cross-service combined report is eventually consistent, not a distributed transaction. Refresh after new posting; the separate reconciliation command remains authoritative for delivery integrity. Direct aggregates suit the verified small dataset; no materialized views, cache service or production-scale performance claim is introduced.
