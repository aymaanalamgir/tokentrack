# Demo data

The three fictional companies that make up the demo, with twelve months of organizational, usage, financial and agent history. Everything is synthetic: people, names, projects, offices, outcomes and spend. None of these companies is a real business, and nothing here describes a real company's operations or portfolio history.

The data flows through the existing system unchanged: usage CSV v1 → Kotlin validation (including Rails membership checks) → pricing → transactional outbox → Rails posting → ledger. No expense row is inserted directly.

## Quick start

```bash
docker compose up -d
./scripts/setup-demo.sh --profile demo     # or --profile smoke (~10%)
```

Use one profile per database: funding is keyed by profile and the second profile is refused. Every step is idempotent; rerunning imports reports duplicates and moves no totals.

| Command | What it does |
| --- | --- |
| `scripts/setup-demo.sh [--profile demo\|smoke] [--seed 42]` | Migrate, generate, load historical pricing, fund, import usage, price, deliver until drained, import agent runs, create controls and requests, apply one correction, reconcile |
| `scripts/generate-enterprise-demo.sh [--profile] [--seed 42] [--start YYYY-MM-01] [--company slug,…]` | Seeds the companies in Rails, exports their snapshot, writes files to `demo/enterprise/generated/<profile>-seed<seed>/` |
| `bin/rails enterprise_demo:seed\|fund\|controls\|summary` | Individual Rails steps (`COMPANY=alset`, `PROFILE=smoke`) |
| `bin/usage snapshot --organizations alset,northline-financial,memento-ai` | Snapshot of all people in those tenants, with offices and fixture references |
| `bin/usage generate-enterprise-demo --spec … --snapshot … --output-dir … --seed 42 --profile demo` | Workload generator |

## Sources of truth

- `demo/enterprise/companies-v1.json` (built by `demo/enterprise/build-spec.py`): departments, teams, headcounts, offices, functions, intensity tiers, workflows, projects, agents, activity patterns, funding plan, controls. Rails and Kotlin both read it, so structure and workload cannot drift apart.
- `demo/enterprise/pricing-historical-v1.json`: synthetic historical rate schedules and per-company mappings.
- Generated files are git-ignored. They are reproducible from the spec, the Rails snapshot, seed and profile; `manifest.json` records counts and a SHA-256 per file.

## Companies

| | Alset | Northline Financial | Memento AI |
| --- | --- | --- | --- |
| Type | Global EV, hardware and technology | Toronto payments fintech | AI meeting-intelligence startup |
| People | 1,100 | 260 | 30 |
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
| Department head | Rhea Castellanos, VP Vehicle Software (manager persona) | Tobias Wren, VP Engineering | Jonah Whitfield, CTO (manager persona) |
| Team manager with capped delegation | | Elliot Brandt, Payments Core lead; also leads Real-Time Payments Platform | |
| Project lead (may also start projects) | Dev Raman, Perception (Autonomous Driving Intelligence) | Mateo Alvarez, Fraud Research (Fraud Detection Engine); no reports | Ines Kowalski, ML (Transcription & Summarization Engine) |
| Employee | Lena Okafor, Infotainment | Hana Takeda, Payments Core; reports to Elliot; Data Platform working group | Theo Brennan, Full-Stack |
| Colleague | | Iris Calloway, Product Design; contributes to Fraud Detection Engine | |

More identities at each level, all with only the grants their position implies: Alset adds Kamala Ferreira (VP Autonomous Systems & AI, department head), Lucia Zhang (Data Science Manager), Dariusz Castro (technical lead, Perception), Karim Lim (data scientist), Omar Castro (product designer) and Javier Valdez (account executive); Northline adds Priyanka Doshi (Head of Risk), Lars Delgado (Compliance Lead), Thandi Ferreira (product manager), Rania Lim (data engineer), Felix Kapoor (mobile engineer) and Hamza Tanaka (support specialist); Memento AI adds Elena Gallagher (Head of AI), Kofi Mensah (ML engineer), Samir Haddadi (backend engineer), Priya Natarajan (product manager), Thandi Quintero (product designer) and Amir Eriksen (growth marketer). The picker opens on the company with the most identities, Northline.

Leadership does not imply financial write authority: only the financial operator grant does (at Memento the founder holds both).

### Structure rules

- Each department has a head who reports to the company leader; each team has a manager who reports to the head (Memento's small teams other than AI & ML report to the department head directly). Teams with more than 12 individual contributors get technical leads, one per ten people, so no one manages more than 16 people. Memento's teams have no managers: engineers report to the CTO, everyone else to the CEO.
- Department heads and team managers hold `team_manager` grants on their unit. The largest department (about 155 people) stays inside the 200-person analytics scope bound. Team sizes are scaled to the headcount in `build-spec.py`; Northline's Payments Core and Fraud Research stay at 13 so their members report straight to the team lead.
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

Controls in the final three months: a personal ceiling and project sublimits for each employee persona, a capped allowance delegation to the Alset and Northline managers, and a few requests (personal allowance, project funding, team funding) in 2026-10, routed by the existing approval rules. Northline's set is the request scenario: Hana's $180 request routes to Elliot (within his $300 cap), her $450 request routes to the CFO and is rejected, Mateo's $1,500 project request exceeds the October reserve and fails safely when approved, and his $400 request can be approved. `agents:demo_correction` then corrects one agent-linked Memento AI charge.

## Results

Recorded 2026-11-16 on the development stack built from an empty database with `./scripts/setup-demo.sh` (demo profile, seed 42). Generated `manifest.json` SHA-256 `14720226b47608b4d7c2bf00a7d84d8a4cb6b58ef8c8c61b72680ff0f4a61ceb`.

| | Alset | Northline Financial | Memento AI |
| --- | ---: | ---: | ---: |
| People | 1,100 | 260 | 30 |
| Usage events | 99,551 | 36,863 | 17,101 |
| People with usage | 1,020 | 220 | 30 |
| Priced and posted events | 94,589 | 36,327 | 16,627 |
| Agent runs (all linked to usage) | 12,948 | 7,494 | 3,998 |
| Run success rate (concluded runs) | 89.9% | 91.6% | 87.6% |
| Corrected spend, 12 months | $267,233.84 | $51,059.13 | $37,924.91 |
| Funded (reserve) | $356,698.51 | $67,381.57 | $53,632.92 |
| Spend per person | $243 | $196 | $1,264 |

Spend is whatever the ledger posted from the workload; no total was targeted. Utilization is about 75% at Alset and Northline and 71% at Memento, with individual account-months both over and well under budget because spend per person varies widely around a plan built on tier averages.

### Agent findings

Designed changes surface as Insights findings. On Northline, comparing 2026-09-01 → 2026-11-01 with the two months before (Agents → Insights with that range): Fraud Triage Agent retry rate +10.7 points (12.2% → 23.0%) and Reconciliation Agent success rate −16.9 points (95.7% → 78.8%). Every agent also shows a pricing-coverage gap, because 1.5% of its usage runs on the unpriced self-hosted model. Alset's Fleet Diagnostics Agent degrades from 2026-07 and Memento's Evaluation Harness Agent from 2026-07 (month-over-month comparisons ending 2026-08-01).

### Reconciliation

`bin/usage reconcile`: `balanced_with_unpriced_usage`; 147,543 priced = 147,543 posted; 5,972 unpriced events; zero pending, dead, unresolved owners, missing postings, amount discrepancies, duplicate expenses or unbalanced transfers; net expenditure 356,217.883977165 USD (including the one documented correction).

### Performance (Docker Desktop, 8 GB VM)

| Step | Time |
| --- | --- |
| Seed and generate (demo profile) | 32 s |
| Fund 12 months (3 companies) | 21 s |
| Import usage (one call per company, 36 monthly batches) | 76 s (previously about 6 min as 36 separate CLI calls) |
| Price | about 80 s |
| Deliver to the ledger | about 40 min: 32 events/s before the V9 claim indexes, about 90 events/s after |
| Reconcile (whole database) | about 7 min |
| Whole setup | 51 min, of which about 15 min were spent before the claim fix took effect; expect about 35 min now |

Delivery was capped by the outbox claim query, which scanned and sorted the whole queue on every batch (`FOR UPDATE SKIP LOCKED` rules out a parallel scan). Migration V9 adds partial indexes and the claim now runs two index-ordered queries (expired leases, then due work). Organization analytics over twelve months for Alset still takes several seconds: the Rails ledger aggregation reruns its correction-aware query for each breakdown.

### Tests

The Rails suite seeds Northline Financial and Memento AI and addresses people by persona; `spec/models/enterprise_demo_spec.rb` also checks the scenario structure. `EnterpriseDemoGeneratorTest` covers determinism, the twelve-month window, canonical rows, roll-up labelling, run linkage, membership coverage and the smoke subset. `./scripts/verify.sh` passed all 15 checks (lint, typecheck, unit, Rails, Kotlin unit and integration, eight browser suites) against this database.

## Limitations

- Roll-ups place a half-month's interactive spend on one day inside the period, so daily charts are approximate within a period; weekly-to-monthly views and all totals are exact.
- Synthetic historical rates are assumptions; the rate-only savings comparison therefore reports "unavailable" for these companies.
- Delivery (about 90 events/s locally) and reconciliation still dominate setup time.
- The start date is fixed once a database has seeded the companies.
