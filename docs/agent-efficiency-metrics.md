# Agent efficiency metrics

The `/agents` report has one authorized run population supplied by Rails. Kotlin applies that population before aggregating definitions, runs, attempts, and linked usage. Directory visibility never expands private execution scope.

- Run counts use explicit imported outcomes: success, failure, cancelled, and incomplete (`unknown`). TokenTrack does not infer outcomes from token use or cost.
- Retry count is `max(attempt_count - 1, 0)` per run. Retry rate is runs with at least one retry divided by runs. Average retries is over every run in the cohort.
- Duration is completion minus start; running records are excluded from average duration.
- Input/output/cached-input totals come from canonical usage events linked by organization, source, and run ID. Cached input remains a subset of input.
- Corrected modeled cost comes only from Rails posted ledger entries, including correction descendants. Cost per success is total corrected cohort expenditure divided by explicit successes; average successful-run cost includes only costs linked to successful runs.
- Cost completeness is `complete` only when every linked event is priced and delivered. Otherwise shown costs are known posted costs and labelled partial; no estimate fills the gap.

Times are UTC and ranges are half-open. Runs are included by `started_at`. Group totals are alternate views of the same population and should not be added together.

Slice 9B adds these derived metrics, computed once in Kotlin (`InsightRules.derive`) and never recomputed elsewhere:

- Success rate is successes divided by concluded runs (success + failure + cancelled). Running/unknown runs are excluded, not counted as failures. No concluded runs gives null.
- Tokens per run (input, output, cached input, total) divide by runs that have at least one linked usage event, so unlinked runs are not treated as zero-token runs.
- Median duration uses completed runs; it is the basis for duration findings.
- Pricing coverage is priced events divided by linked usage events.
- Cost per run, failed-run cost and its share, and adjustments (net minus original expenditure) are computed in Rails from the ledger.

Run-linked cost is attributed to the run by its start time, whatever the timestamps of its usage events. The cohort is no longer capped at 5,000 runs; see [agent optimization](agent-optimization.md) for comparisons, thresholds and findings.

Still out of scope: productivity scores, forecasts, predictions, and any statement of cause.
