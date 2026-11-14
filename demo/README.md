# Fictional organizational demo

Run `docker compose exec core-api bin/rails db:migrate db:seed`, then open <http://localhost:3000>. Choose an organization and person; the header menu switches identity again.

| Organization | Structure | People | Projects |
| --- | --- | --- | --- |
| Northstar Labs | Four mostly flat teams | 10 | 3 |
| Aperture Technologies | Twelve units with departments/nested teams | 64 | 5 |

| Aperture identity | Job | Grants and experience |
| --- | --- | --- |
| Olivia Chen | CTO | Organization viewer and explicit project creator; leadership |
| Marcus Rivera | Engineering Manager | Platform team manager plus Developer Productivity project lead |
| Priya Shah | Product Manager | Fraud Detection and Customer Analytics project lead; delegated project creator; no contributor line-management authority |
| Jordan Lee | Software Engineer | Employee; Platform home team, additional Data & AI membership, Fraud Detection and Developer Productivity contributor |
| Sofia Patel | UX Designer | Employee; Product Design home team, including Fraud Detection collaboration |

Northstar includes Maya Chen (founder/leadership), Theo Park (technical lead/team manager), Leila Shah (project lead), Sam Rivera (engineer), Nia Brooks (designer), and other fictional functions. Maya also has an explicit project creation grant. Titles never grant authority.

Seeds use stable UUIDs derived from lookup keys and `.example` email domains. Seeding is transactional and idempotent; repeating it restores declared attributes/memberships without duplicates. Rails seeds create no usage, spending, budget, or approval records; Slice 4 imports synthetic token events separately through Kotlin.

To intentionally delete and recreate **only flagged demo organizations and their sessions**:

```bash
docker compose exec core-api bin/rails demo:reset
```

This destroys edits inside demo tenants only when no append-only financial history exists. Slice 5 refuses reset for a financially initialized tenant; preserve that audit trail. Non-demo tenants are preserved. Seeding/reset require demo mode in development/test; production always rejects demo entry.

The picker is local impersonation, not real identity proofing. Each selection still gets a genuine backend session and server-enforced access scope. Organizational data and displayed counts come from PostgreSQL.

Fraud Detection includes Engineering, Product, Design, and Data/AI contributors under Priya's explicit project grant; engineers continue reporting to their engineering managers. Marcus can inspect his reports' project links but cannot staff Fraud Detection. Jordan appears in multiple projects as one stable User record. Expand each project's primary-team groups on demand. Lead collaboration labels remain separate from authorized administration.

Seeds restore declared fixture IDs, expected memberships/roles, and explicit administration on seeded projects. Rejoining through the application creates a new membership period; seeding intentionally restores its stable declared fixture period. User-created projects and their history remain unless the demo-only reset is requested.


## Synthetic usage (Slice 4)

After backend credential setup and Compose startup, run:

```bash
demo/generators/generate-usage.sh 2026-11-10 2026-12-10 42
docker compose exec usage-engine bin/usage import /app/demo/fixtures/usage-events-v1.csv --source demo-synthetic-v1
docker compose exec usage-engine bin/usage list
```

The checked-in snapshot/manifest and CSV capture an explicit simulated thirty-day window, both organizations, all job functions/home teams, cross-functional projects, engineering/agent spikes, weekday/weekend differences, and unassigned activity. Provider/model identifiers are fictional dimensions. No prompts, completions, prices, costs, or productivity scores are generated.

Use the saved snapshot to reproduce exact events, or re-export current Rails demo data to reflect changes. Real recorded project membership periods constrain assignments; generation does not invent historical membership. The standard dates intentionally overlap known membership periods. Choose new explicit dates after a later reset if necessary. Current archived projects are excluded from generated choices; historical imported attribution still supports them under the documented policy.

The small invalid fixture includes valid events, identical/conflicting duplicates, unsupported versions, invalid fields, unknown references, and a foreign-tenant user. The malformed fixture retains complete valid rows before an unterminated quote. Expect exit 2 for completed validation rejections and 3 for malformed/partial imports; inspect stored reports rather than relying on process exit alone. Reimporting the same source/events never changes the original events. Rails demo:reset does not delete Kotlin usage history.

See [generator inputs](generators/README.md), [CSV contract](../contracts/usage-event-v1.md), and [Slice 4 verification](../docs/slice4.md).

## Pricing and financial scenarios (Slice 5)

Original CSV/snapshot/manifest remain unchanged. `demo/generators/generate-pricing-scenarios.sh` reads the saved organization snapshot and writes a separate `pricing-scenarios-v1.csv`, imported with stable source `demo-pricing-scenarios-v1`. It selects Jordan Lee through recorded cross-project membership rather than a Kotlin hardcoded employee ID. Ten explicit simulated events cover five baseline models, cached versus uncached mini, a clearly hypothetical effective-date change, unknown pricing, and unsupported cache writes. Eight supported events total 0.78366 USD; two intentionally remain unpriced. Dates November 15/25 are simulated, not evidence of completed real usage.

The original illustrative model identifiers map explicitly to pricing profiles; the local/demo-small-v1 → Gemini mapping is a synthetic proxy, not a claim of Google usage. Conservative profile limits leave 440 original main events unpriced. Do not change fingerprints or inflate workloads to hide this limitation.

Run [development commands](../docs/development.md#slice-5-pricing-and-finance-operations) to initialize synthetic funding, price, deliver and reconcile. `finance:demo_setup` is an explicit local action granting financial_operator to Maya/Olivia separately from normal seeds; funding is 100,000 USD per organization/month, not actual spend. [Slice 5 report](../docs/slice5.md) traces Jordan's Fraud Detection expense, a 3,000 USD Platform-to-project transfer, duplicate HTTP replay, and an append-only correction. Finance exists in backend operations; no new dashboard is implied.

## Analytics walkthrough (Slice 6)

Reuse the current canonical events and financial ledger; no extra usage fixture or reset is required. Generate a separate backend analytics token, migrate, and run `bin/rails analytics:demo_access` inside core-api to explicitly grant manager/project-lead account read examples. This command grants no financial mutation authority.

1. Enter as Olivia and open Analytics. The default range follows the recorded demo dates. Inspect corrected net expenditure, unpriced coverage and current-home-team activity.
2. Choose Engineering, then Fraud Detection Platform. Model and employee drill-down preserve dates. Funded accounts represent separate account-owned expenditure across full UTC accounting months.
3. Compare Models and Tools; original fictional names remain visible alongside synthetic pricing profiles. Open measured weekly contributors to inspect token components and model/tool/project changes.
4. Switch to Marcus. His team scope combines with his explicit Developer Productivity lead grant; cross-team activity is restricted to that project. Budget readers see only explicitly granted accounts.
5. Switch to Priya and inspect Fraud Detection contributor activity; opening Jordan does not grant Jordan's unrelated private project history.
6. Switch to Jordan. Only personal consumption appears; coworker and team-wide API requests are denied, and organizational allocations are restricted.
7. Change granularity, use a custom empty range, and inspect loading/retry and light/dark responsive states. Export downloads only the authorized report JSON.

Comparisons outside the recorded historical window show partial coverage rather than fabricated ordinary growth percentages. Tokens measure consumption, not productivity. Reports cover modeled metered usage, excluding fixed subscriptions and unsupported billing scenarios. [Slice 6](../docs/slice6.md) records actual totals and tests.

## Operational budgets and personal controls (Slice 7)

Run the explicit `budgets:demo_setup` rake task after migrations. Jordan starts with a 500 USD ceiling, 250 Fraud Detection and 150 Developer Productivity capacity, leaving 100 unallocated. These are controls, not funded accounts; actual consumption remains the existing modest dataset. Personal partitions for other used projects remain zero until explicitly assigned and can warn despite overall capacity remaining.

Marcus receives an explicit 1,000 USD maximum delegation for direct reports in Platform Engineering during the demo months. He can edit Jordan's ceiling within that cap, but cannot edit unrelated employees or transfer funding. Priya sees authorized project budgets and project-specific contributor expense, without unrelated personal ceilings. Olivia can manage own-tenant financial operations and delegation.

Sofia's explicitly small 0.05 USD ceiling demonstrates actual posted overage without adding a fictional 275 USD charge. Optional `SMALL_BUDGET_SCENARIO=true` returns unused December Fraud Detection funding to reserve through an audited, repeatable transfer; the retained project allocation is near 95% utilized and its recorded-day run rate projects an overage. Organization funding and expense totals remain unchanged.

Use the accounting-month selector and forecast-only as-of date, inspect warning/coverage labels, adjust multiple personal partitions atomically and review a transfer before confirming. Employee allocations never create financial transactions. Transfers retain actor, reason, date, accounting month and source/destination legs. Full-month totals and recorded-date estimates are distinct. [Slice 7 report](../docs/slice7.md) records the actual current values after browser demonstrations; [control rules](../docs/budget-allowances.md) explain unused-capacity floors and eligible projects.

The browser budget workflow intentionally appends immutable personal revisions and distinct authorized 3 USD UI transfers. Its stable-key 3,000 USD transfer replays without duplication. Do not reset history to repeat the walkthrough.

## Funding requests and approvals (Slice 8)

Run `docker compose exec core-api bin/rails requests:demo_setup`, then open `/requests?month=2026-11`.

1. Jordan's 750 USD desired ceiling routes to Marcus because his active cap is 1,000 USD. Approval adds one allowance revision and no ledger transaction.
2. Jordan's 1,500 USD request routes directly to Olivia because authority applies to the final ceiling, not incremental increases.
3. Priya's 2,000 USD Fraud Detection request and Marcus's 3,000 USD Platform request require financial-operator review; neither requester can self-approve.
4. Sofia's rejected example appears in History with no allowance or ledger effect.
5. The retained Platform-backed Fraud request demonstrates insufficient source capacity: approval fails safely and stays pending. The reserve-backed example demonstrates a successful conserved transfer.

Identical decision retries return the existing result. Revoking Marcus's delegation before decision removes his approval authority. Request events and submitted terms are append-only, and approved execution references link to the existing allowance or financial audit record. [Slice 8](../docs/slice8.md) records the verified workflow.

## Agent insight scenarios (Slice 9B)

`generators/generate-agent-insight-scenarios.sh 42` writes `agent-insights-usage-v1.csv` and `agent-insights-executions-v1.jsonl` for the separate source `demo-agent-insights-v1`; `agent-insights-pricing-v1.json` maps its models to published rates. Seven fictional Aperture agents cover a retry spike, a success-rate decline, output-token growth, a model-mix change, volume growth without inefficiency, incomplete pricing, sparse data and one corrected charge. Outcomes are simulated (`synthetic_fixture`), and the UI labels them. Load order and observed results are in [Slice 9B](../docs/slice9b.md).

Walkthrough: enter as Olivia, open Agents → Efficiency, expand Support Summarizer's cost drivers, open Insights, filter to "Retry increase", show the evidence and follow "View supporting runs". Switch to Marcus, then Jordan, to see the same agents recomputed from their narrower populations.

## Agent executions (Slice 9A)

After usage import, generate and import the separate sidecar:

```bash
generators/generate-agent-executions.sh 42 demo-synthetic-v1
docker compose exec usage-engine bin/usage agent-import /app/demo/fixtures/agent-executions-v1.jsonl --source demo-synthetic-v1
```

The generator selects actual existing usage run IDs and is byte-for-byte deterministic for the same database, source, and seed. It writes no usage or ledger rows. Open `/agents` and switch identities to verify organization, team/project, and self scopes. See [Slice 9A](../docs/slice9a.md).
