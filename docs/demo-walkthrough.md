# Demo walkthrough

A repeatable tour of TokenTrack on the fictional Northline Financial tenant, with Alset for scale and Memento AI as a second tenant. Every step reads real stored data; nothing is reset between runs. The data covers 2025-11-01 to 2026-11-01 (UTC); pages opened without a range land on the latest recorded month, October 2026.

## Before you start

```bash
docker compose up --build -d
./scripts/setup-demo.sh
```

Open <http://localhost:3000>. The identity picker opens on Northline Financial; switch identity at any time from the header menu. Each switch creates a real server session with that person's scope.

| Identity | Grants | Use it to show |
| --- | --- | --- |
| Amara Lindqvist (CEO) | Organization viewer, project creator | The whole tenant |
| Gabriel Moreau (CFO) | Financial operator, organization viewer | Funding, transfers, approvals |
| Elliot Brandt (Payments Core lead) | Team manager, Real-Time Payments Platform lead, $300 allowance delegation | A manager's bounded view and delegated approval |
| Mateo Alvarez (Fraud Research) | Fraud Detection Engine lead, project creator | Project scope without line-management authority |
| Hana Takeda (Backend Engineer) | Employee | Personal usage, allowance and requests |

## 1. Leadership overview (Amara Lindqvist, then Gabriel Moreau)

1. Choose **Amara Lindqvist**. The overview shows 260 people across 15 departments and three offices; **Organization** opens any department down to its people.
2. Switch to **Gabriel Moreau** and open **Analytics**. Set the range to 2025-11-01 → 2026-11-01 with monthly granularity: about $51,000 of corrected spend over the year. Point out pricing coverage below 100%: usage on the self-hosted model has no pricing profile, and its cost is shown as unknown rather than zero.
3. Use **Explore expenditure** to switch between teams, projects, models and tools; selecting a row filters the page. Each breakdown reconciles to the same total, and they are not meant to be added together. **Detailed records** at the bottom holds the full tables and the ledger audit.

## 2. Manager (Elliot Brandt)

1. Switch to **Elliot Brandt**. Navigation shows "My teams"; Analytics covers Payments Core plus the Real-Time Payments Platform project he leads, not the organization.
2. Open **My teams** and then Hana. Her project memberships are listed while her home team stays Payments Core: cross-functional work does not move a reporting line.
3. Open **Budgets** (October 2026). Elliot sees his reports' ceilings with **Manage ceiling**, limited to the $300 cap Gabriel delegated. Moving funding needs the separate financial-operator grant, which a manager title does not imply.

## 3. Employee (Hana Takeda)

1. Switch to **Hana Takeda**. Analytics shows only her own consumption.
2. Open **Budgets**. The personal allowance shows her monthly ceiling and per-project sublimits. **Adjust allocations** rebalances sublimits within the ceiling; capacity a project has already used can't be taken away, and an amount above the ceiling disables Save. Sublimits and ceilings are controls, not money.
3. Open **Requests**. "My requests" lists her $180 allowance request (routed to Elliot, within his cap) and her $450 request (routed to Gabriel because it exceeds the cap, and rejected).

## 4. Financial approval

1. On a freshly loaded demo, the $180 request is pending with Elliot: switch to **Elliot Brandt → Requests → Pending review**, open it and choose **Approve & execute**. It adds an allowance revision and no ledger entry. If it is already approved, open it from History to show the decision event.
2. Switch to **Gabriel Moreau → Requests → Pending review**. Mateo's $400 Fraud Detection Engine request executes one balanced transfer from the reserve in the same transaction as the decision. His $1,500 request exceeds the reserve's October balance: approving it fails safely and it stays pending with no execution.
3. Open **Budgets → Funding movement history** to show the transfer with actor and reason. Total authorized funding is unchanged by transfers.

Approving requests is permanent history. To demonstrate without consuming a scenario, open an already-decided request and walk through its event timeline.

## 5. Agent intelligence (Gabriel Moreau)

1. Open **Agents**. The overview shows runs, outcomes, retries, tokens and corrected cost, with an agent explorer; outcomes are marked as synthetic.
2. Open **Insights** with the range 2026-09-01 → 2026-11-01 (compared with the two months before). The Fraud Triage Agent's retry rate rose 10.7 points (12.2% → 23.0%) and the Reconciliation Agent's success rate fell 16.9 points (95.7% → 78.8%). **Show evidence** lists what else changed in the same periods, labelled as not causes; **View supporting runs** opens exactly the retried executions.
3. On **Efficiency**, expand the Reconciliation Agent's cost drivers: the exact split separates volume from per-run cost.
4. Every agent also shows a pricing-coverage gap: part of its usage has no price, so its cost is incomplete rather than estimated.
5. Switch to Elliot, then Hana: the same agents are recomputed from their narrower populations.

## 6. Financial correctness

```bash
docker compose exec usage-engine bin/usage reconcile
```

- `status: balanced_with_unpriced_usage` means the ledger matches every priced event, and some usage is deliberately unpriced. It is not a discrepancy.
- `priced_events` equals `posted_events`; `amount_discrepancies`, `duplicate_expenses`, `unbalanced_transfers` and `delivered_missing_postings` are 0.
- One documented correction (a Memento AI agent charge) shows corrected cost: the ledger audit lists it as the original, a reversal and an adjustment, never an edit.
- Run `./scripts/setup-demo.sh` again: every import reports duplicates and the totals do not move.

## 7. Scale and isolation

- Choose **Alset → Nole Perfume** and open Analytics for 2025-11-01 → 2026-11-01: 1,100 people across five offices and about $267,000 of corrected spend. A year of the largest company takes a few seconds to aggregate.
- Choose **Memento AI → Noor Haddad**: a 30-person startup with the highest spend per employee. Nothing from Northline or Alset is visible from here.

## Tips

- If a page looks empty, check the month or range is inside 2025-11 → 2026-10.
- Budget overruns are real: spend is never dropped when an account exceeds its plan.
