# Demo walkthrough

A repeatable tour of TokenTrack on the fictional Aperture Technologies tenant. Every step reads real stored data; nothing is reset between runs. All dates are simulated (2026-11-10 to 2026-12-10), so pick months and ranges inside that window.

## Before you start

```bash
docker compose up --build -d
./scripts/setup-demo.sh
```

Open <http://localhost:3000>. Switch identity at any time from the header menu; each switch creates a real server session with that person's scope.

| Identity | Grants | Use it to show |
| --- | --- | --- |
| Olivia Chen (CTO) | Organization viewer, financial operator | The whole tenant, funding, approvals |
| Marcus Rivera (Engineering Manager) | Platform team manager, Developer Productivity lead, capped allowance delegation | A manager's bounded view and delegated approval |
| Priya Shah (Product Manager) | Fraud Detection and Customer Analytics lead | Project scope without line-management authority |
| Jordan Lee (Software Engineer) | Employee | Personal usage, allowance and requests |

## 1. Leadership overview (Olivia Chen)

1. Choose **Aperture Technologies → Olivia Chen**. The overview shows the organization structure, teams and projects.
2. Open **Analytics**. Set the range to 2026-11-01 → 2026-12-11. Point out net expenditure next to the pricing-coverage figure: part of the usage has no supported pricing profile, and its cost is shown as unknown rather than zero.
3. Scroll to the team, project, model and tool breakdowns. Click a project to drill in; the date range is preserved. Each breakdown reconciles to the same total and they are not meant to be added together.

## 2. Engineering manager (Marcus Rivera)

1. Switch to **Marcus Rivera**. Navigation now shows "My teams"; Analytics covers his managed people plus the Developer Productivity project he leads, not the organization.
2. Open **People** or **My teams** and open a report. Their project memberships are listed while their home team stays Platform Engineering: cross-functional work does not move someone's reporting line.
3. Open **Budgets** at month 2026-11. Marcus sees employee ceilings for his direct reports with **Manage ceiling**, limited to the cap Olivia delegated (visible to Olivia under "Explicit allowance delegation"). Moving funding needs the separate financial-operator grant, which a manager title does not imply.

## 3. Employee (Jordan Lee)

1. Switch to **Jordan Lee**. Analytics shows only Jordan's own consumption.
2. Open **Budgets**, month 2026-11. The personal allowance panel shows the monthly ceiling and the per-project sublimits. **Adjust allocations** rebalances sublimits within the ceiling; an amount above the ceiling disables Save. Sublimits and ceilings are controls, not money: they never change funding.
3. Open **Requests**. "My requests" lists Jordan's allowance requests with the approver each was routed to and why. **New request** starts another.

## 4. Financial approval

1. On a freshly initialized demo the $750 allowance request is pending with Marcus (it is within his delegated cap): switch to **Marcus Rivera → Requests → Pending review**, open it and choose **Approve & execute**. If it is already approved, open it from History instead and show the decision event and the allowance revision it produced.
2. Switch to **Olivia Chen → Requests → Pending review**. The $1,500 request was routed to her because it exceeds Marcus's cap; project and team funding requests are also hers as financial operator. Approving a funding request executes one balanced transfer in the same transaction as the decision.
3. Open **Budgets → Funding movement history** to show the resulting transfer with actor and reason. Total authorized funding is unchanged by transfers.

Approving requests is permanent history. To demonstrate without consuming a scenario, open an already-decided request and walk through its event timeline.

## 5. Agent intelligence (Olivia Chen)

1. Open **Agents**. Overview shows runs, outcomes, retries, tokens and corrected cost; a note marks the outcomes as synthetic demo fixtures.
2. **Efficiency** compares the last 14 recorded days with the 14 before. Expand **Support Summarizer**: its cost per success more than doubled, the exact split shows no volume effect, and the model-mix table shows usage moving to a costlier model. Then look at **Docs Indexer**: runs more than doubled, cost per success is flat, and it has no finding.
3. **Insights**: filter to "Retry increase". PR Review Assistant's retry rate rose from 4.8% to 23.8%. **Show evidence** lists the recorded attempts and what else changed in the same periods, labelled as not causes. **View supporting runs** opens exactly those executions.
4. Filter to "Model cost concentration" and show the rate-only comparison: it is labelled hypothetical and lists what it ignores.
5. Under "Not compared", Incident Scribe has three runs per period and is reported as insufficient data instead of a finding.
6. Switch to Marcus, then Jordan: the same agents are recomputed from their narrower populations, and agents outside their scope disappear.

## 6. Financial correctness

```bash
docker compose exec usage-engine bin/usage reconcile
```

- `status: balanced_with_unpriced_usage` means the ledger matches every priced event, and some usage is deliberately unpriced. It is not a discrepancy.
- `priced_events` equals `posted_events`; `amount_discrepancies`, `duplicate_expenses`, `unbalanced_transfers` and `delivered_missing_postings` are 0.
- `authorized_adjustment_delta_usd` is the sum of explicit corrections. Originals are never edited: the ledger audit table at the bottom of **Analytics** lists a corrected charge as its original, a reversal and an adjustment.
- Run `./scripts/setup-demo.sh` again: every import reports duplicates and the totals do not move.

## Tips

- If a page looks empty, check the month or date range is inside the simulated window.
- December's Fraud Detection project account is intentionally small and shows a budget warning; recorded spend is never dropped when a limit is exceeded.
- Northstar Labs (Maya Chen) is a second tenant for showing that nothing crosses organizations.
