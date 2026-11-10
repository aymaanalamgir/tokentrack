# Model pricing

The bundled catalogue is `services/usage-engine/src/main/resources/pricing/catalogue-v1.json`. Rates are configuration, never calculator constants. USD prices per million standard first-party text tokens, reviewed November 9, 2026:

| Provider | Model | Input | Cached read | Output | Source |
| --- | --- | ---: | ---: | ---: | --- |
| OpenAI | gpt-5.4 | 2.50 | 0.25 | 15.00 | [Official pricing](https://developers.openai.com/api/docs/pricing) |
| OpenAI | gpt-5.4-mini | 0.75 | 0.075 | 4.50 | [Official pricing](https://developers.openai.com/api/docs/pricing) |
| Anthropic | claude-sonnet-4-6 | 3.00 | 0.30 | 15.00 | [Official pricing](https://platform.claude.com/docs/en/about-claude/pricing) |
| Anthropic | claude-haiku-4-5 | 1.00 | 0.10 | 5.00 | [Official pricing](https://platform.claude.com/docs/en/about-claude/pricing) |
| Google | gemini-2.5-flash | 0.30 | 0.03 | 2.50 | [Official pricing](https://ai.google.dev/gemini-api/docs/pricing) |

These catalogue entries apply from November 1, 2026 UTC to cover the simulated dataset. This is a **demo applicability snapshot**, not a claim that a provider introduced these prices on that date. `verified_at` records the separate source review date. Standard rates do not imply support for every request at those model names.

## Identity and supported billing profiles

Mappings match the exact ingestion source, original provider, and original model. Canonical identities/fingerprints never change:

| Source | Original provider/model | Pricing profile |
| --- | --- | --- |
| demo-synthetic-v1 | openai/demo-code-v1 | openai/gpt-5.4-mini |
| demo-synthetic-v1 | anthropic/demo-reasoning-v1 | anthropic/claude-sonnet-4-6 |
| demo-synthetic-v1 | local/demo-small-v1 | google/gemini-2.5-flash, explicitly synthetic proxy |

All demo mappings declare `synthetic_standard_cache_read`. They simulate standard text requests whose cached-input category means **cache reads only**. Real integrations must explicitly attest `attested_standard_cache_read` in a source-specific mapping. Recognizing a real model name alone does not establish billing semantics. Missing prices produce `MISSING_RATE`; a recognized model without billing metadata produces `INSUFFICIENT_BILLING_METADATA`.

Configured demo limits are input ≤200,000, output ≤64,000 and input+output ≤200,000 tokens. Exceeding them produces `UNSUPPORTED_PROFILE`; 440 original main-fixture events are deliberately left unpriced. These conservative bounds avoid pretending every generated workload fits the supported context/tier. They are not comprehensive provider context-window specifications.

V1 excludes Anthropic cache writes and retention variants, Gemini cache storage, batch/priority/regional pricing, long-context premiums, tools, media, discounts, taxes, and currency conversion. GPT-5.4 long-context input above 272K has separate billing treatment ([model documentation](https://developers.openai.com/api/docs/models/gpt-5.4)); this profile does not enter that band. Unsupported basis/tier metadata is rejected rather than assigned a three-category estimate.

## Effective dates and immutability

Resolution requires exact provider/model/tier/USD and `effective_from <= occurred_at < effective_until`; null end means open. A database advisory lock and overlap trigger serialize competing schedules. Missing or ambiguous resolution cannot produce an expense. Source-keyed mappings are immutable.

Rates and provenance cannot be rewritten or deleted. To introduce a future rate, first use `bin/usage close-rate --id RATE_UUID --until 2027-01-01T00:00:00Z`, then load a separately identified successor through `load-prices --file /app/prices.json`. Closure is allowed only on an open interval, after its start, with no already-priced event at/after the proposed boundary. Row locks serialize pricing with closure. Previously persisted snapshots retain their original interval/provenance. Update the custom catalogue's interval before reloading it; conflicting existing IDs fail instead of silently changing a rate.

The bundled `synthetic/effective-change-example` explicitly simulates input 3.00 before November 20 and 2.50 afterward, with cached 0.30/0.25 and output 15.00. Its `urn:tokentrack:synthetic:price-change` provenance identifies a hypothetical schedule, not provider history.

## Exact precision

Rates use NUMERIC(18,9). Costs and ledger amounts use NUMERIC(38,15); API money uses decimal strings. Kotlin BigDecimal computes `(input-cached)*input_rate/1000000 + cached*cached_rate/1000000 + output*output_rate/1000000`, storing each component at scale 15 with `RoundingMode.UNNECESSARY`. Integer tokens and nine-place rates fit exactly; unexpected loss of precision fails. PostgreSQL checks the equations and component sum. Rails uses BigDecimal and validates the supplied component sum, without repricing tokens.

There is no cent rounding at posting: every microcharge retains all 15 places. Aggregate first; round only for future display/invoice presentation. A one-token rate of 0.000000001 yields 0.000000000000001 USD. The mini example is 0.0600 + 0.0015 + 0.0450 = **0.1065 USD**, versus 0.1200 without cached reads.
