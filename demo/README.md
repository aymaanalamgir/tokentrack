# Fictional organizational demo

Run `docker compose exec core-api bin/rails db:migrate db:seed`, then open <http://localhost:3000>. Choose an organization and person; the header menu switches identity again.

| Organization | Structure | People | Projects |
| --- | --- | --- | --- |
| Northstar Labs | Four mostly flat teams | 10 | 3 |
| Aperture Technologies | Twelve units with departments/nested teams | 64 | 5 |

| Aperture identity | Job | Grants and experience |
| --- | --- | --- |
| Olivia Chen | CTO | Organization viewer; leadership |
| Marcus Rivera | Engineering Manager | Platform team manager plus Developer Productivity project lead |
| Priya Shah | Product Manager | Fraud Detection and Customer Analytics project lead; no contributor line-management authority |
| Jordan Lee | Software Engineer | Employee; Platform home team, additional Data & AI membership, cross-functional projects |
| Sofia Patel | UX Designer | Employee; Product Design and assigned projects |

Northstar includes Maya Chen (founder/leadership), Theo Park (technical lead/team manager), Leila Shah (project lead), Sam Rivera (engineer), Nia Brooks (designer), and other fictional functions. Titles never grant authority.

Seeds use stable UUIDs derived from lookup keys and `.example` email domains. Seeding is transactional and idempotent; repeating it restores declared attributes/memberships without duplicates. No spending, token, budget, or approval records are seeded.

To intentionally delete and recreate **only flagged demo organizations and their sessions**:

```bash
docker compose exec core-api bin/rails demo:reset
```

This destroys edits inside demo tenants. Non-demo tenants are preserved. Seeding/reset require demo mode in development/test; production always rejects demo entry.

The picker is local impersonation, not real identity proofing. Each selection still gets a genuine backend session and server-enforced access scope. Organizational data and displayed counts come from PostgreSQL.
