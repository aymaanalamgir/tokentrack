# Fictional demo data

With the stack running, `./scripts/setup-demo.sh` loads everything below and is safe to repeat. Then follow the [demo walkthrough](../docs/demo-walkthrough.md). [Demo data](../docs/enterprise-demo-data.md) documents the companies, the workload model, funding and the verified results.

| Path | Contents |
| --- | --- |
| `enterprise/companies-v1.json` | The three companies: departments, teams and sizes, offices, job functions and their AI intensity, projects, agents, personas, activity curves, funding plan and controls. Read by both the Rails seed and the Kotlin generator. |
| `enterprise/build-spec.py` | Builds `companies-v1.json` (`python3 demo/enterprise/build-spec.py demo/enterprise/companies-v1.json`). Edit this, not the JSON. |
| `enterprise/pricing-historical-v1.json` | Synthetic historical rates (provider `synthetic`, labelled as such) for the twelve-month window. |
| `enterprise/generated/` | Git-ignored output of `scripts/generate-enterprise-demo.sh`: per-month usage CSV and agent-execution JSONL per company, the snapshot used and a manifest of SHA-256 hashes. |

## Companies

| Company | People | Offices | Projects | Role scenarios |
| --- | --- | --- | --- | --- |
| Alset | 1,100 | Austin, Palo Alto, Toronto, Berlin, Shanghai | 8 | Nole Perfume (CEO), Ingrid Vasquez (CFO), Rhea Castellanos (VP Vehicle Software), Kamala Ferreira (VP Autonomous Systems & AI), Lucia Zhang (Data Science Manager), Dev Raman (Perception manager and project lead), Dariusz Castro (technical lead), Lena Okafor (engineer), Karim Lim (data scientist), Omar Castro (designer), Javier Valdez (account executive) |
| Northline Financial | 260 | Toronto, Montreal, New York | 7 | Amara Lindqvist (CEO), Gabriel Moreau (CFO), Tobias Wren (VP Engineering), Priyanka Doshi (Head of Risk), Elliot Brandt (Payments Core lead), Lars Delgado (Compliance Lead), Mateo Alvarez (Fraud Detection Engine lead), Hana Takeda (engineer), Iris Calloway (designer), Thandi Ferreira (product manager), Rania Lim (data engineer), Felix Kapoor (mobile engineer), Hamza Tanaka (support specialist) |
| Memento AI | 30 | New York | 6 | Noor Haddad (founder; leadership and finance), Jonah Whitfield (CTO), Elena Gallagher (Head of AI), Ines Kowalski (project lead), Kofi Mensah (ML engineer, Evaluation Harness lead), Samir Haddadi (backend engineer), Theo Brennan (full-stack engineer), Priya Natarajan (product manager), Thandi Quintero (designer), Amir Eriksen (growth marketer) |

Only the listed people are demo identities in the picker (they span executive, department head, team manager, technical lead and individual contributor levels, so each level's view can be shown); everyone else exists for realistic rosters, reporting lines and usage. Titles never grant authority: every permission is an explicit role grant created by the seed.

Northline's people have the structure the access-control, approval and test scenarios rely on: Hana reports directly to Elliot (Payments Core has no technical leads), Elliot reports to Tobias, Mateo leads Fraud Detection Engine and may start projects but has no reports, Hana also belongs to the Data Platform Engineering working group, and both Hana and Iris contribute to Fraud Detection Engine.

## Seeding and reset

`bin/rails db:seed` (run by the setup script) creates the companies with stable UUIDs derived from lookup keys and `.example` email domains. It is transactional and idempotent: re-running restores descriptive attributes but never rewrites recorded membership periods, because usage validation and charge attribution depend on them. `DEMO_COMPANIES=northline-financial,memento-ai` limits seeding to some companies (the test suite does this).

`bin/rails demo:reset` deletes and reseeds only flagged demo organizations, and refuses once any request, spending-control or ledger history exists, so financial history is never rewritten. Seeding and reset require demo mode in development or test; production rejects demo entry.

The identity picker is local impersonation, not identity proofing. Each selection still gets a real backend session and server-enforced scope.

## Workload, funding and controls

The individual steps, all run by `setup-demo.sh`:

```bash
./scripts/generate-enterprise-demo.sh --profile demo --seed 42      # seed + snapshot + generate files
docker compose exec usage-engine bin/usage load-prices --file /app/demo/enterprise/pricing-historical-v1.json
docker compose exec core-api env PROFILE=demo bin/rails enterprise_demo:fund
docker compose exec usage-engine sh -c 'bin/usage import /app/demo/enterprise/generated/demo-seed42/memento-ai/usage-*.csv --source enterprise-memento-v1'
docker compose exec usage-engine bin/usage price --source enterprise-memento-v1
docker compose exec usage-engine bin/usage deliver --limit 10000 --workers 8
docker compose exec usage-engine sh -c 'bin/usage agent-import /app/demo/enterprise/generated/demo-seed42/memento-ai/executions-*.jsonl --source enterprise-memento-v1'
docker compose exec core-api bin/rails enterprise_demo:controls
docker compose exec core-api bin/rails agents:demo_correction
docker compose exec usage-engine bin/usage reconcile
```

`import` and `agent-import` accept several files; each file is still its own idempotent batch. Funding is created through `Finance::Operations` with stable keys, never by inserting ledger rows. Controls add personal ceilings and project sublimits for the employee personas in the last three months, a capped allowance delegation to each company's manager persona, and a few requests (Northline's over-cap request is rejected by the CFO so request history has a rejection). `agents:demo_correction` applies one documented, idempotent correction to an agent-linked Memento AI charge so corrected cost differs from original cost.
