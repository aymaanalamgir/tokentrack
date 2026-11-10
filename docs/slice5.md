# Slice 5 — pricing and financial ledger

Implementation and local verification completed November 10, 2026 UTC. Official rate review is separately dated November 9. Started on `main` at reviewed commit `010b6b2295366f7cdcd65885353b39161749e6c4`, with a clean working tree. No database resets or canonical replacements were performed. [Machine-readable results](verification/slice5-results.json) record the final database reconciliation.

## A. Summary

Kotlin now resolves effective-dated configurable model prices, calculates exact component costs, persists immutable provenance and creates a transactional delivery outbox. Rails now owns monthly budget accounts, explicit financial authority, project/team attribution, idempotent charge receipts, append-only funding/expense entries, conservative transfers, explicit reversals/replacements and reconciliation. Existing ingestion, organization, project and browser workflows remain operational. No analytics dashboard or approval UI was added.

The original main fixture has 7,737 events. An additional six pre-existing ingestion-verification events were also present at the start. All **7,743** original event IDs/fingerprints remain intact. Ten separate deterministic pricing-scenario events bring canonical count to **7,753**.

## B. Pricing architecture

[Model pricing](model-pricing.md) documents official sources, baseline values, explicit original-model mappings, assumptions and exclusions. Seven rates comprise five baseline models plus two explicitly hypothetical effective-date examples. Ten source-specific mappings preserve original identities; the local model's Google profile is a labeled synthetic proxy. Rate verification date and demo applicability date are distinct.

Selection uses exact provider/model/tier/USD and half-open effective intervals. PostgreSQL overlap checks serialize concurrent schedules. Existing snapshots never reprice. Controlled open-interval closure takes locks shared with pricing and refuses to invalidate existing snapshots. A successor rate has its own UUID. No fictional provider price history is asserted.

BigDecimal and NUMERIC calculate `(input-cached)*input_rate/1000000 + cached*cached_rate/1000000 + output*output_rate/1000000`. Nine-place rates and 15-place costs use exact division with UNNECESSARY rounding. Ledger posting retains all 15 places; there is no per-call cent rounding. Missing rates, unsupported context/profile and insufficient metadata remain separate actionable outcomes.

Actual main fixture result: **7,297 priced**, **440 unsupported**, **500.012050275 USD**. Separate scenarios: **8 priced**, **2 intentionally unpriced**, **0.78366 USD**. Final all-source diagnostic run priced zero additional records, reported 7,305 already priced, seven missing rates and 441 unsupported profiles. Six original validation-source events have no configured pricing mapping; the remaining missing/unsupported examples are intentional scenarios. Costs were not inflated to fit an impressive total.

## C. Financial architecture

[Financial ledger](financial-ledger.md) describes reserve/unit/project/unassigned accounts, monthly UTC periods, derived funding/expense balances and database constraints. The explicit local setup created 100,000 USD of synthetic allocation per organization for each of November and December; this is funding, not expenditure. Normal seeds assign no finance authority. Maya/Olivia received separate organization financial_operator grants only through explicit financial setup.

Rails resolves project membership at usage time, funded project first, then established home-team account, then explicitly funded unassigned. Unknown project history or no eligible funded owner holds the receipt. Expenses can exceed allocation and report negative availability; incurring an expense does not authorize discarding it. Historical archive/inactive status does not erase otherwise valid costs. Tenant-bound FKs and operation authorization protect all owned dimensions.

## D. Event delivery

[Priced usage event v1](../contracts/priced-usage-event-v1.md) defines the separate backend financial token and immutable payload. Snapshot/outbox commit together. Workers use SKIP LOCKED claims, tokenized leases, durable attempts, bounded concurrency and bounded retry/dead cycles. Only a matching committed-post response is acknowledged. Rails receipt/charge/entry commit together; canonical-usage uniqueness and advisory locking serialize duplicates.

A refused Rails connection was exercised through a temporary worker URL override: two attempts became retryable, while priced snapshots remained durable. Main pricing itself ran with Rails reference URL unavailable and still priced independently. The first actual HTTP batch exposed a Rails autoload error for financial exception constants; moving each exception to its own Zeitwerk file fixed it. Autoload verification and the full test suites passed afterward. A five-event batch then posted, followed by 7,300 more, including retried outage/error attempts: **7,305 delivered, zero remaining retries/dead/leases**. The recorded outage attempts remain in delivery history.

## E. Worked database example

All following values came from the actual delivered supplemental fixture, not a hand-written expected record. Scenario dates are simulated future usage within the demo window.

| Dimension | Actual value |
| --- | --- |
| Source event | `scenario-mini-cached-d99956be3c8f` |
| Canonical usage UUID | `d5c7c82a-2092-4a82-b48e-c92ffe1d27f6` |
| Canonical fingerprint | `a63327ac29eda8c026f68cec274a258740ca43d42f129139bee1811b713c211f` |
| Employee | Jordan Lee, `bb103120-91a9-1720-41c4-3ee41b76c7d2` |
| Home team | Platform Engineering, `06d4100c-08a5-5ca7-29c6-3e077f182760` |
| Project | Fraud Detection Platform, `85d9c854-6924-05a9-bfc9-5c7f0882bd55` |
| Occurred at | `2026-11-15T14:30:00.000000Z` |
| Provider/model | openai / gpt-5.4-mini |
| Input / cached subset / output | 100,000 / 20,000 / 10,000 |
| Input / cached / output rates per million | 0.75 / 0.075 / 4.50 USD |
| Component costs | 0.0600 + 0.0015 + 0.0450 USD |
| Exact original charge | **0.1065 USD** |
| Rate UUID | `de4ce333-7e81-58ea-a307-d25cb7bca0d0` |
| Mapping UUID | `e6bbf232-9814-5494-b058-afdda4be0164` |
| Priced event / receipt UUID | `7a7c938a-2336-4714-bf24-1f7066396a9a` |
| Original financial transaction UUID | `547a814f-82a5-44d7-a7a0-7c3a45dbebd3` |
| Charged budget account | Fraud Detection Platform, `2457fc4a-7d28-b5d1-5a6c-6feb98cea25c` |
| Ledger entry UUID | `7b45af3c-66f1-4716-8376-072582a0b087` |

The uncached comparison costs 0.1200 USD. Equivalent Sonnet tokens cost 0.3960 USD. Other supported scenarios exercise GPT-5.4, Haiku and Gemini; hypothetical pre/post-change costs are 0.045 and 0.040 USD. Original costs persist after later rate selection.

Two actual authenticated HTTP replays returned **200**, duplicate=true, the same original transaction and original amount, with the original usage_charge count staying **1 → 1**. They were performed after the correction and still acknowledged the original immutable charge.

## F. Financial correctness

An authorized 3,000 USD transfer from Platform Engineering to Fraud Detection produced two opposite funding legs. Aperture November aggregate funding was exactly **100,000 before and after**. Repeating the same operation key returned the existing transaction `b4d403b2-d5ff-410d-90d0-b55967ff1f5b`.

The worked charge was explicitly reversed and replaced with 0.1000 USD through the financial operator command. Original 0.1065 remains; appended reversal -0.1065 and replacement +0.1000 give net 0.1000, a -0.0065 delta. Correction transaction IDs are `0ae6a874-dc9f-435b-8e2a-2878f4f928b9` and `1e7a59b9-c600-4137-bcff-22a7b59f8da9`. Retrying the same correction key returned the existing pair. Tests also reject a second distinct reversal, foreign-tenant actors and implicit title/viewer authority.

Final actual reconciliation:

| Check | Result |
| --- | ---: |
| Priced snapshots / original expense posts | 7,305 / 7,305 |
| Pending delivery / dead / unresolved owner | 0 / 0 / 0 |
| Missing postings / missing outbox | 0 / 0 |
| Amount discrepancies / payload conflicts | 0 / 0 |
| Duplicate original expenses | 0 |
| Unbalanced transfers / invalid operation entries | 0 / 0 |
| Posted receipts missing original transactions | 0 |
| Immutable priced / gross original ledger total | 500.795710275 USD |
| Linked authorized adjustment delta | -0.0065 USD |
| Net expenditure | 500.789210275 USD |
| Unpriced usage | 448 |

Status is **balanced_with_unpriced_usage**, CLI exit **2**, not a claim of complete billing coverage. The 448 comprise 440 unsupported original main events, six original verification-source events without prices and two intentional scenario failures. Reconciliation independently checks original transaction and original ledger amounts, source fingerprint, canonical/posted usage IDs, delivery acknowledgement and actual correction entries. It cannot hide an original mismatch inside a net adjustment. Automated tests inject amount/missing-post discrepancies and verify detection.

## G. Executed verification

| Executed check | Actual result |
| --- | --- |
| Pre-change Rails baseline | 80 examples, zero failures |
| Pre-change Kotlin suites | 47 tests, zero failures |
| Final `bundle exec rspec` | **106 examples, zero failures** |
| Final `gradle test integrationTest` | **76 tests: 47 unit + 29 real PostgreSQL, zero failures** |
| `bin/rails zeitwerk:check` | All is good |
| Frontend lint / typecheck | Passed |
| Frontend unit tests | **5 passed** |
| Chromium smoke suite | Passed: health, layout, themes, navigation, refresh, 404 recovery |
| Chromium access suite | Passed: persona/tenant boundaries, sessions, manager/project scopes, cache isolation, CSRF, logout |
| Chromium project suite | Passed: creation, membership/history, ownership revocation, archive/restore, responsive themes |
| Production Docker builds | Rails, Kotlin and frontend passed |
| Rails development/test migrations | Applied additive financial migrations successfully |
| Flyway history | V1–V5 successful |
| Live Rails/Kotlin/frontend health | All HTTP 200, database connected/UP |
| Canonical identity checksum | Original 7,743 rows unchanged: `9a78ff0e3d0032ffe1c66fcc8a0688eb` |
| Repricing main fixture | 0 newly priced, 7,297 already priced, 440 unsupported |
| Cross-schema writes | Both foreign-schema CREATE and foreign-table INSERT denied |
| `git diff --check` | Passed |

Checksum definition: `md5(string_agg(id::text || payload_fingerprint, ',' ORDER BY id))` restricted to the four original sources. The supplemental source is intentionally excluded. Original CSV/snapshot/manifest, Flyway V1 and historical Slice 1–4 reports are unchanged. No development ledger cleanup or database reset ran. Browser tests leave their normal archived review project. Recent successful delivery/reconciliation runtime logs have no new 500/exception errors after the autoload fix. Configured local secrets were checked against changed source files; `.env` remains ignored and no secret value was written to documentation/results.

Real PostgreSQL tests cover overlap/concurrent pricing, lease expiry/stale ACKs, bounded retries, concurrent workers, source/immutability guards, simultaneous Rails expense posting, competing transfers and correction races. Test cleanup is isolated to test source/tenant records; privileged DDL cleanup in tests is not a runtime financial mutation feature.

## H. Files changed

- Kotlin: pricing resolver/calculator/catalogue/scenario generator; outbox repository/HTTP client/worker/reconciler; CLI commands and backend token configuration; calculation, HTTP-client and PostgreSQL pricing/delivery tests.
- Usage database: additive Flyway V2 pricing/delivery, V3 numeric/append-only integrity, V4 source guards and V5 controlled schedule closure. Canonical V1 unchanged.
- Rails: financial models, explicit policy grant, source contract/poster/charge resolver, operations/demo setup/reconciliation, separate internal financial controller/shared service authentication concern and trusted rake commands.
- Business database: additive ledger/integrity migrations and regenerated SQL schema snapshot; normal organizational identities preserved.
- Fixtures/config: separate ten-row CSV/generator, Compose financial token wiring and `.env.example` entry. No frontend finance component or public proxy exposure.
- Documentation: README, architecture/development/contracts/demo guides, this report, pricing policy, ledger policy, exact priced-event contract and machine-readable verification results.

## I. Known limitations

Only declared standard text/cache-read profiles are supported. Cache writes/retention, storage, media/tools, batch/priority/regional pricing, taxes/discounts, currency conversion and long-context premiums need richer future usage metadata and pricing rules. Unsupported original workloads remain visible and unpriced. Future real-source integrations need explicit billing attestations; model-name recognition alone is insufficient.

Home-team history is conservative because Slice 4 stores current organizational membership rather than full effective-dated employment history. Project membership periods are recorded. Future richer history can improve attribution without mutating original costs. Rate snapshots deliberately reflect the configured demo applicability date, not invented historical provider changes.

Workers are explicit bounded CLI invocations, without an always-running scheduler. Financial commands are trusted local developer operations behind explicit actor authorization; production finance UX/auth, invoices, approval workflows and funding requests are deferred. DML guards do not prevent a privileged database owner from changing DDL. No external invoicing or provider API was called.

## J. Slice 6 readiness

Stable usage/user/home-team/project/model/time dimensions, immutable price components and separate funding/expense ledgers support organization expenditure, team trends, project utilization, employee consumption, model comparisons, weekly/monthly aggregation and net-versus-gross views. Future analytics must use one authoritative original charge plus linked corrections, preserve unknown/unpriced coverage and avoid duplicating project costs across team groupings. Build scoped read contracts and dashboards next; they were deliberately not implemented here.

Reproduce with the [development commands](development.md#slice-5-pricing-and-finance-operations). Existing financially initialized tenants must retain their append-only history; repeat setup/operations idempotently instead of resetting.
