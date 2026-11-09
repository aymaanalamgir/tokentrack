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

This destroys edits inside demo tenants. Non-demo tenants are preserved. Seeding/reset require demo mode in development/test; production always rejects demo entry.

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
