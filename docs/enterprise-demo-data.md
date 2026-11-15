# Enterprise demo data

Three additional fictional companies with twelve months of organizational, usage, financial and agent history. Everything is synthetic: people, names, projects, offices, outcomes and spend. None of these companies is a real business, and nothing here describes a real company's operations or portfolio history.

The data flows through the existing system unchanged: usage CSV v1 → Kotlin validation (including Rails membership checks) → pricing → transactional outbox → Rails posting → ledger. No expense row is inserted directly, and the original demo companies are not touched.

## Quick start

```bash
docker compose up -d                                  # core-api needs the read-only ./demo mount
./scripts/setup-demo.sh                               # optional: the original demo companies
./scripts/setup-enterprise-demo.sh --profile demo     # or --profile smoke
```

Use one profile per database: funding is keyed by profile and the second profile is refused. Every step is idempotent; rerunning imports reports duplicates and moves no totals.

| Command | What it does |
| --- | --- |
| `scripts/generate-enterprise-demo.sh [--profile demo\|smoke] [--seed 42] [--start YYYY-MM-01] [--company slug,…]` | Seeds the companies in Rails, exports their snapshot, writes files to `demo/enterprise/generated/<profile>-seed<seed>/` |
| `scripts/setup-enterprise-demo.sh [--profile] [--seed]` | Generate, load historical pricing, fund, import usage, price, deliver until drained, import agent runs, create controls and requests, reconcile, summarize |
| `bin/rails enterprise_demo:seed\|fund\|controls\|summary` | Individual Rails steps (`COMPANY=alset`, `PROFILE=smoke`) |
| `bin/usage snapshot --organizations alset,northline-financial,memento-ai` | Snapshot of all people in those tenants, with offices and fixture references |
| `bin/usage generate-enterprise-demo --spec … --snapshot … --output-dir … --seed 42 --profile demo` | Workload generator |

## Sources of truth

- `demo/enterprise/companies-v1.json`: departments, teams, headcounts, offices, functions, intensity tiers, workflows, projects, agents, activity patterns, funding plan, controls. Rails and Kotlin both read it, so structure and workload cannot drift apart.
- `demo/enterprise/pricing-historical-v1.json`: synthetic historical rate schedules and per-company mappings.
- Generated files are git-ignored. They are reproducible from the spec, the Rails snapshot, seed and profile; `manifest.json` records counts and a SHA-256 per file.

## Companies

| | Alset | Northline Financial | Memento AI |
| --- | --- | --- | --- |
| Type | Global EV, hardware and technology | Toronto payments fintech | AI meeting-intelligence startup |
| People | 750 | 175 | 18 |
| Departments / teams | 16 / 39 | 15 / 20 | 5 / 8 |
| Offices | Austin (HQ), Palo Alto, Toronto, Berlin, Shanghai | Toronto (HQ), Montreal, New York | New York |
| Projects | 8 | 7 | 6 |
| Agents | 6 | 5 | 5 |
| Source namespace | `enterprise-alset-v1` | `enterprise-northline-v1` | `enterprise-memento-v1` |

Demo identities (shown in the identity picker; other employees are not):

| Role | Alset | Northline Financial | Memento AI |
| --- | --- | --- | --- |
| Leadership (organization viewer, project creator) | Nole Perfume, CEO | Amara Lindqvist, CEO | Noor Haddad, CEO & founder |
| Financial operator (and organization viewer) | Ingrid Vasquez, CFO | Gabriel Moreau, CFO | Noor Haddad |
| Team manager (department head) | Rhea Castellanos, VP Vehicle Software | Tobias Wren, VP Engineering | Jonah Whitfield, CTO |
| Project lead | Dev Raman, Perception (Autonomous Driving Intelligence) | Mateo Alvarez, Fraud Research (Fraud Detection Engine) | Ines Kowalski, ML (Transcription & Summarization Engine) |
| Employee | Lena Okafor, Infotainment | Hana Takeda, Payments Core | Theo Brennan, Full-Stack |

Leadership does not imply financial write authority: only the financial operator grant does (at Memento the founder holds both).

### Structure rules

- Each department has a head who reports to the company leader; each team has a manager who reports to the head. Teams with more than 12 individual contributors get technical leads, one per ten people, so no one manages more than 16 people. Memento's teams have no managers: engineers report to the CTO, everyone else to the CEO.
- Department heads and team managers hold `team_manager` grants on their unit. The largest department (about 105 people) stays inside the 200-person analytics scope bound.
- `users.office` is directory metadata shown next to job titles. It grants nothing and is not part of any financial identity. Offices also set each person's working hours for event timestamps.
- Project memberships are dated: projects starting later in the year have later joins, members join over the first 20 days, and about 10% rotate off after four to eight months. Usage is attached to a project only while a recorded membership covers it, so Rails reference validation and charge attribution accept every event.
- Home-team memberships are recorded at the company epoch (2025-10-01), before the window, so charges attribute to home teams for the whole year.

## Workload rules

Twelve months, 2025-11-01 to 2026-11-01 UTC (half-open). Configurable `--start` (first of a month) applies only to a database that has not yet seeded these companies.

Each job function has an intensity tier, a project share and weighted workflows:

| Tier | Interactive calls per active working day | Adoption mix (daily / weekly / occasional / none) | Used for |
| --- | --- | --- | --- |
| very_high | 80–240 | 65 / 25 / 8 / 2 % | AI research, autonomy, software, cloud, data science, backend, fraud research, Memento engineers |
| high | 25–75 | 45 / 35 / 15 / 5 % | Embedded, manufacturing, product, frontend, risk analytics, Memento non-engineers |
| moderate | 6–18 | 20 / 35 / 30 / 15 % | Finance (Alset), design, supply chain, marketing, sales, customer success |
| selective | 3–9 | 10 / 30 / 40 / 20 % | Compliance, finance and security at Northline |
| low | 1–4 | 5 / 25 / 40 / 30 % | HR, legal, Alset compliance |

Per person: an adoption class, an intensity jitter (0.6–1.5×) and an adoption start up to a few months in, so usage grows unevenly. Per day: a company monthly curve (launch spikes, December dip), weekend factor (12% Alset, 10% Northline, 35% Memento) and holiday dips. Frontier-model share drifts over the year: up at Alset and Memento, down at Northline as it shifts to cheaper models.

Two kinds of event:

- **Agent runs** (agentic workflows such as code review, fraud triage, meeting summarization): 2–10 linked events per run, each one model call within normal request limits, plus one extra call per retry. Each run has an execution JSONL record with attempts and a synthetic outcome drawn from the agent's profile; several agents degrade later in the year (for example Alset's Fleet Diagnostics Agent and Memento's Evaluation Harness Agent), so the Insights tab has real changes to find.
- **Interactive roll-ups**: one event per person, interactive workflow and half-month period (1st–15th, 16th–end of month) holding the summed tokens of that period's calls, timestamped on a working day inside the period. Their source models end in `-rollup` and have their own pricing mapping (larger token limits) and description, so a roll-up is never mistaken for a single provider request. Periods never cross a month and rates change only on month boundaries, so pricing the sum costs exactly what pricing each call would. Daily charts place a period's spend on one of its days; weekly and monthly views are exact.

Roll-ups exist because individual calls at realistic volumes would be millions of rows. Agent runs are kept as individual calls because run-level efficiency analytics needs real per-run linkage.

## Pricing

The published catalogue rates in this repository start on 2026-11-01. The enterprise window is earlier, so the companies are priced with separate **synthetic historical schedules** under provider `synthetic` (`frontier-2025`, `balanced-2025`, `fast-2025`), flagged `synthetic: true`, sourced to `example.invalid`. They are demo assumptions, not verified provider rates, and no verified 2026 rate is backdated. The frontier schedule has a price cut on 2026-05-01 (3.00/0.30/15.00 → 2.50/0.25/12.50 USD per million input/cached/output tokens) to exercise effective dating; balanced is 0.75/0.075/4.50 and fast 0.30/0.03/2.50.

Each company also uses a self-hosted model (`local/demo-selfhosted-v1`) with no pricing profile (5% of Alset events, 1.5% Northline, 3% Memento). Those events stay unpriced and their cost is unknown, not zero.

The Slice 9B rate-only comparison considers only non-synthetic published rates, so it reports "unavailable" for these companies.

## Funding and controls

Monthly funded accounts (reserve, unassigned, every unit, every project) are created through `Finance::Operations#fund` and `#transfer` by each company's financial operator. Allocations follow a planning assumption, not observed spend: a monthly budget per person by tier (for example $55 for very-high users at Alset, $180 at Memento), split between home team and active projects in the same proportion the generator uses, multiplied by a monthly budget curve, the profile scale and per-account factors (some accounts deliberately under- or over-funded). The reserve receives the allocations plus a 10–15% buffer. Utilization therefore differs by account, and growth outpacing the budget curve produces genuine over-budget months; recorded spend is never dropped.

Controls in the final three months: a personal ceiling and project sublimits for each employee persona, a capped allowance delegation to the Alset and Northline managers, and a few requests (personal allowance, project funding, team funding) in 2026-10, routed by the existing approval rules.

## Results

Recorded 2026-11-15 on a disposable Compose project built from empty volumes (base demo, then `setup-enterprise-demo.sh --profile demo --seed 42`). Generated `manifest.json` SHA-256 `61753b52165352233197c40fd8e42abd59fb5555cf8c6b06908c7720847157e9`; two consecutive generations produced identical hashes.

### Organizations

| | Alset | Northline Financial | Memento AI |
| --- | --- | --- | --- |
| People | 750 | 175 | 18 |
| Departments / teams | 16 / 39 | 15 / 20 | 5 / 8 |
| Offices | 5 (Palo Alto 196, Toronto 170, Austin 164, Berlin 136, Shanghai 84) | 3 (Toronto 123, Montreal 34, New York 18) | 1 |
| Reporting lines | 749 | 174 | 17 |
| Largest span of control | 16 | 15 | 10 |
| Projects / memberships (rotated off) | 8 / 352 (30) | 7 / 93 (11) | 6 / 37 (1) |

### Usage, agents and spend

| | Alset | Northline Financial | Memento AI |
| --- | --- | --- | --- |
| Usage events | 67,812 | 24,538 | 10,514 |
| Roll-ups / agent-call events | 30,669 / 37,143 | 4,966 / 19,572 | 612 / 9,902 |
| People with usage | 695 | 149 | 18 |
| Agent runs (all linked to usage) | 8,844 | 4,979 | 2,436 |
| Run success rate | 89.9% | 91.8% | 87.8% |
| Pricing coverage (events) | 94.9% | 98.5% | 97.4% |
| Corrected spend, 12 months | $177,243.43 | $35,362.06 | $22,276.59 |
| Spend per person | $236 | $202 | $1,238 |

Monthly corrected spend (USD, rounded):

| Month | Alset | Northline | Memento |
| --- | ---: | ---: | ---: |
| 2025-11 | 4,636 | 1,287 | 470 |
| 2025-12 | 8,573 | 2,069 | 596 |
| 2026-01 | 12,469 | 3,236 | 1,374 |
| 2026-02 | 13,294 | 2,965 | 1,417 |
| 2026-03 | 15,692 | 3,146 | 2,251 |
| 2026-04 | 18,849 | 3,645 | 2,427 |
| 2026-05 | 14,851 | 3,314 | 1,986 |
| 2026-06 | 16,512 | 3,053 | 2,071 |
| 2026-07 | 15,446 | 3,002 | 2,244 |
| 2026-08 | 17,379 | 2,913 | 2,058 |
| 2026-09 | 20,320 | 3,148 | 2,782 |
| 2026-10 | 19,222 | 3,582 | 2,599 |

Spend is whatever the ledger posted from the workload; no total was targeted. These figures were identical in two independently built databases.

### Funding

| | Funded (reserve) | Spent | Organization utilization | Account-months over budget | Account-months under 50% |
| --- | ---: | ---: | ---: | ---: | ---: |
| Alset | $243,804.34 | $177,243.43 | 72.7% | 172 of 709 (24%) | 289 |
| Northline Financial | $48,716.32 | $35,362.06 | 72.6% | 96 of 430 (22%) | 207 |
| Memento AI | $32,638.84 | $22,276.59 | 68.3% | 60 of 198 (30%) | 87 |

Overruns are more frequent than "occasional": spend per person varies widely (daily versus occasional adopters), so small team accounts swing around a plan built on tier averages. Raise `budget_usd` or the per-account factors in the spec to reduce them; funding cannot be changed in place once posted.

### Agent findings

Designed changes surface as Insights findings (Agents → Insights, Compare: month over month, end date shown):

- Alset, July vs June 2026: Fleet Diagnostics Agent success rate −22.7 points (93.2% → 70.5%, critical) and retry rate +18.2 points (9.1% → 27.3%).
- Memento AI, July vs June 2026: Evaluation Harness Agent retry rate +28.1 points (16.4% → 44.4%, critical).
- Northline Financial, August vs July 2026: Fraud Triage Agent retry rate +15.6 points (3.2% → 18.8%).

### Reconciliation

`bin/usage reconcile` on the whole database (base demo plus the three companies): `balanced_with_unpriced_usage`; 107,639 priced = 107,639 posted; 4,602 unpriced events; zero pending, dead, unresolved owners, missing postings, amount discrepancies, duplicate expenses or unbalanced transfers. A full rerun of the setup script changed no counts or totals (112,241 events, 19,405 runs, 108,986 transactions, net 235,451.538154535). During one build Docker stopped the stack mid-delivery; after restarting, the outbox leases expired and delivery resumed with no duplicates.

### Performance (local Docker Desktop, 8 GB VM)

| Step | Time |
| --- | --- |
| Generate (demo profile, 102,864 events) | 9–24 s |
| Fund 12 months (3 companies) | 86 s |
| Import 36 monthly CSVs | about 4.5 min (6–9 s each) |
| Price | about 50 s |
| Deliver to the ledger | about 55 min (about 33 events/s with 8 workers) |
| Reconcile (whole database) | 4–6 min |
| Whole setup | about 65 min; a no-op rerun about 16 min |

Requests as Alset's CEO through the Next.js proxy (median of three warm calls): agent insights 210–345 ms, agent overview over 12 months 1.45 s, budgets 58 ms, requests 107 ms, run drill-down 31 ms. Organization analytics takes 1.7 s for the default 30 days and 4.9 s for twelve months: the Rails ledger aggregation reruns its correction-aware query for each breakdown (about 450 ms each over 65,000 receipts). Computing all breakdowns in one pass would fix this.

### Tests

`spec/models/enterprise_demo_spec.rb` (hierarchy, spans, uniqueness, offices; seeding, idempotent reseed, funding through operations, one-profile guard; snapshot export) and `EnterpriseDemoGeneratorTest` (determinism, twelve-month window, canonical rows, roll-up labelling, run linkage, membership coverage, smoke subset) pass, and all eight browser suites pass against a database that contains the enterprise companies.

## Limitations

- Roll-ups place a half-month's interactive spend on one day inside the period, so daily charts are approximate within a period; weekly-to-monthly views and all totals are exact.
- Synthetic historical rates are assumptions; the rate-only savings comparison therefore reports "unavailable" for these companies.
- Delivery throughput (about 33 events/s locally) dominates setup time.
- The start date is fixed once a database has seeded the companies.
