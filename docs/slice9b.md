# Slice 9B — Agent efficiency intelligence

Slice 9B adds period comparisons, deterministic anomaly detection, a cost-driver breakdown and evidence-backed findings to the Agents workspace. Definitions, thresholds, the API and limitations are in [agent optimization](agent-optimization.md).

## What changed

- **Kotlin:** `AgentQuery` (shared scope parsing), `AgentInsights`, `InsightRules`, `Periods`, `InsightThresholds`, the paged `agent-cohort` endpoint, a `retried` filter, and `AgentInsightScenarioGenerator` with the `generate-agent-insight-scenarios` CLI command. The 5,000-run cap and the `cohort_runs` array are gone.
- **Rails:** `Agents::CostAggregator`, a batched `Agents::LedgerCosts`, `Agents::Insights`, `Agents::InsightText`, `GET /api/v1/agents/insights`, the additive `receipts_agent_run_link` index, and the `agents:demo_correction` task.
- **Frontend:** Agents now has Overview, Efficiency, Insights and Executions tabs; the proxy allowlists `agents/insights` and its filters.
- **Demo:** separate source `demo-agent-insights-v1` (usage CSV, execution JSONL, pricing mappings).

## Demo scenarios

```bash
docker compose restart usage-engine
demo/generators/generate-agent-insight-scenarios.sh 42
docker compose exec usage-engine bin/usage load-prices --file /app/demo/fixtures/agent-insights-pricing-v1.json
docker compose exec usage-engine bin/usage import /app/demo/fixtures/agent-insights-usage-v1.csv --source demo-agent-insights-v1
docker compose exec usage-engine bin/usage price --source demo-agent-insights-v1
docker compose exec usage-engine bin/usage deliver --limit 10000 --workers 4
docker compose exec usage-engine bin/usage agent-import /app/demo/fixtures/agent-insights-executions-v1.jsonl --source demo-agent-insights-v1
docker compose exec core-api bin/rails agents:demo_correction
docker compose exec usage-engine bin/usage reconcile
```

Dates are fixed (2026-11-12 to 2026-12-10 UTC, behaviour changing on 2026-11-26) and every draw is a hash of the seed. `price` exits 2 because scenario F deliberately contains unpriced usage. All steps are replay-safe.

| Scenario | Agent | Project | Designed change |
| --- | --- | --- | --- |
| A | PR Review Assistant | Developer Productivity | Retry rate rises |
| B | Test Triage Agent | Fraud Detection | Success rate falls |
| C | Release Notes Writer | Customer Analytics | Output tokens per run grow |
| D | Support Summarizer | Knowledge Automation | Model mix shifts to a costlier model |
| E | Docs Indexer | Developer Productivity | Volume more than doubles, per-run efficiency unchanged |
| F | Legacy Migration Helper | Fraud Detection | About 30% of usage has no pricing profile; input tokens grow |
| G | Incident Scribe | Developer Productivity | Three runs per period |
| H | Docs Indexer run `ins-docs-indexer-20261126-000` | — | Charge 0.01507 corrected to 0.008 |

## Verified local result (2026-11-13)

Generation produced 1,630 runs and 1,630 usage events (execution file SHA-256 `e9016a6cf164592410cb90e3310917bad861962576973c3c3eaa01abdb8e2b5e`). Import accepted 1,630 events with no rejections; 1,564 were priced and delivered, 66 are intentionally unpriced. Execution import stored 1,630 runs with zero rejected and zero unlinked.

Leadership view, default comparison (2026-11-26 to 2026-12-10 against 2026-11-12 to 2026-11-26):

| Agent | Finding | Previous → current | Evidence quality |
| --- | --- | --- | --- |
| PR Review Assistant | Retry rate +19.0 points | 4.8% → 23.8% (8 → 40 retried runs of 168) | Sufficient |
| Test Triage Agent | Success rate −15.7 points | 93.6% → 77.9% (140 concluded runs each) | Sufficient |
| Release Notes Writer | Output tokens per run +55.3%; cost per success +28.7% | 1,992 → 3,094; $0.0749 → $0.0963 | Sufficient |
| Support Summarizer | Cost per success +111.4% (critical); sonnet is 88.4% of cost | $0.0423 → $0.0894; token share 10.2% → 67.1% | Sufficient |
| Legacy Migration Helper | Input tokens +50.6%; 35 unpriced events; cost per success +27.5% | 30,123 → 45,355; 68.8% priced | Sufficient; cost findings incomplete cost data |
| Docs Indexer | None | 84 → 196 runs, cost per success $0.0166 → $0.0166, adjustment −0.00707 | Sufficient |
| Incident Scribe | None | 3 → 3 runs | Insufficient data |

The Support Summarizer change splits into a volume effect of $0 and a per-run effect of $6.47314005, equal to the ledger change of $5.3308053 → $11.80394535.

The same response holds 63 findings in total because the Slice 9A dataset itself contains a late-window spike: its Code Review and Debugging agents roughly triple tokens per run in the current period, and each has some unpriced usage. Those are real properties of that data, not scenario output. Week over week (2026-12-07 to 12-10 against 11-30 to 12-03) is a partial period compared by elapsed portion. Month over month has no recorded baseline (data starts 2026-11-10), so it reports no findings.

### Financial reconciliation

| | Before | After |
| --- | --- | --- |
| Reconcile status | `balanced_with_unpriced_usage` | `balanced_with_unpriced_usage` |
| Discrepancies, duplicate expenses, missing postings | 0 | 0 |
| Priced and posted events | 7,305 | 8,869 |
| Unpriced events | 448 | 514 |
| Net expenditure, all sources | 500.789210275 | 569.4493173 |
| Net expenditure, pre-existing sources | 500.789210275 | 500.789210275 |
| Adjustment delta | −0.0065 | −0.01357 |

Existing records are unchanged. The increase is the new source's posted charges (68.667177025) and the one scenario H correction (−0.00707). Analytics requests write nothing.

### Performance

Local Docker on the demo dataset (3,146 runs, 8,938 transactions); medians of five warm calls through the Rails services including the Kotlin round trips:

| Query | Median |
| --- | --- |
| Agent overview, 40-day range, 2,918 runs | 91 ms |
| Comparison and insights, previous period | 128 ms |
| Insights, month over month | 48 ms |
| Insights filtered to one agent | 22 ms |
| Overview filtered to one agent's retried runs | 12 ms |
| Cost enrichment alone (cohort walk and ledger) | 38 ms |

Above the old cap, in the test databases: Kotlin overview over 6,200 runs 74 ms, the seven-page cohort walk 34 ms, insights 65 ms (after `ANALYZE`; 7.7 s for the overview without planner statistics on freshly inserted rows); Rails cost enrichment for 6,000 runs in seven cohort calls 79 ms. Receipt lookups use `receipts_agent_run_link` (index scan, one row per run). Cohort paging uses `agent_runs_scope_idx` on the 6,200-run cohort; PostgreSQL picks a sequential scan on the 3,146-row demo table. These are small-dataset measurements, not a production-scale claim.

### Tests

| Command | Result |
| --- | --- |
| `docker compose exec usage-engine gradle test` | 64 passed |
| `docker compose exec usage-engine gradle integrationTest` | 43 passed (real PostgreSQL) |
| `docker compose exec core-api bundle exec rspec` | 173 examples, 0 failures |
| `docker compose exec frontend npm run lint`, `typecheck`, `test` | clean; 17 passed |
| `npm run test:agents` (Slice 9A browser workflow) | passed |
| `npm run test:agent-insights` (Slice 9B browser workflow) | passed |

The browser workflow covers leadership, manager and employee identities, all three comparison modes, the retry drill-down checked against 40 supporting runs and their attempt records, the corrected cost and exact split, the hypothetical scenario label, empty, sparse and error states, internal-route denial, dark desktop and light mobile/tablet layouts, and that Budgets and Requests still load. The frontend production build and the other Slice 2–8 browser suites were not re-run.
