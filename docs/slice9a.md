# Slice 9A — Agent execution tracking

Slice 9A adds persisted, append-only agent definitions, runs, and attempt history in Kotlin without changing canonical usage CSV v1 or Rails financial authority. Execution JSONL v1 imports independently, validates business references through Rails, reports exact replays/conflicts/rejections/unlinked runs, and joins usage only at query time by tenant + source + external run ID.

The deterministic generator reads existing usage run IDs; it never invents a replacement usage dataset and never writes the financial ledger. Seed, source, outcomes, attempts, failure categories, and timestamps are repeatable. An invalid sidecar supports rejection demonstrations.

```bash
docker compose restart usage-engine
demo/generators/generate-agent-executions.sh 42 demo-synthetic-v1
docker compose exec usage-engine bin/usage agent-import /app/demo/fixtures/agent-executions-v1.jsonl --source demo-synthetic-v1
```

`GET /api/v1/agents` is the only browser route. Rails derives the population from `AccessPolicy`, calls backend-only `POST /internal/v1/agent-analytics` with the separate analytics credential, and enriches operational/token results with corrected posted ledger cost. The BFF allowlists only the Rails GET. Client cache keys include organization, identity, effective-scope fingerprint, and complete filter path.

Open `/agents` to filter by UTC dates, authorized project, outcome, agent, or run; inspect cohort metrics, definition comparisons, run history, linked usage, attempt failures, retries, and corrected known cost. Financial gaps are explicit rather than estimated.

See [execution contract](../contracts/agent-execution-v1.md) and [metric definitions](agent-efficiency-metrics.md).

## Verified local result

On 2026-11-11, Flyway applied v7 plus v8 integrity hardening and the seed-42 generator produced 1,516 execution records from existing `demo-synthetic-v1` run IDs. Import stored 20 definitions, 1,516 runs, and 1,969 attempts with zero rejected and zero unlinked records. Exact replay reported 1,516 duplicates; the intentional invalid fixture stored one bounded rejection. Independent regeneration produced the same SHA-256, `3bf4239e4482f6d90ccf1992d589ad3aabdd337ca3cebea626ecd04db4e78fec`.

Before and after execution import, canonical usage remained 7,753 rows. Rails remained 7,433 financial transactions / ledger entries with net expenditure `500.789210275000000`; the sidecar made no financial change.

Verification passed:

- Kotlin unit suite and complete restricted-role PostgreSQL integration suite, including import/replay/conflict/linkage/metrics and internal authentication.
- Rails full suite: 160 examples, including scoped population and corrected-cost descendants.
- Frontend lint, typecheck, 11 unit tests, production build, and the Slice 9A browser workflow across leadership and employee scopes, filters, run drill-down, mobile themes, cache isolation, error handling, and internal-route denial.
