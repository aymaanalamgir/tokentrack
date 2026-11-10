# Priced usage event v1

Backend-only Rails routes, excluded from the Next.js proxy:

- `POST /api/v1/internal/priced-usage-events`
- `POST /api/v1/internal/financial-reconciliation`

Require JSON and `Authorization: Bearer <USAGE_FINANCIAL_TOKEN>` (at least 32 characters). This is a separate write/reconciliation credential from the read-only usage-reference token. Demo cookies, titles and Origins confer no service authority. Replies are private/no-store. Tokens are never forwarded to browsers; redirect following is disabled by the Kotlin client.

## Payload

One flat object, exactly these fields; extra keys (including prompts/completions/arbitrary metadata) are invalid. Required keys with nullable values must still be present.

| Fields | JSON type / semantics |
| --- | --- |
| schema_version, calculation_version | integer 1 |
| priced_event_id, usage_event_id | UUID strings; immutable snapshot UUID and canonical usage UUID |
| organization_id, user_id | UUID strings, tenant-bound |
| project_id | UUID string or null |
| pricing_rate_id, pricing_mapping_id | UUID strings, exact Kotlin provenance |
| source, source_event_id, usage_fingerprint | original ingestion namespace, event identifier, lowercase 64-character SHA-256 |
| provider, model | original immutable usage dimensions |
| pricing_provider, pricing_model, pricing_tier | resolved price dimensions; tier `standard_text_cache_read` |
| billing_basis | `synthetic_standard_cache_read` or explicitly `attested_standard_cache_read` |
| currency | `USD` |
| input_tokens, cached_input_tokens, output_tokens | integer 0–1,000,000,000,000; cached ≤input; positive combined input/output |
| amount, input_cost, cached_input_cost, output_cost | nonnegative decimal strings, ≤15 fractional places |
| input_rate, cached_input_rate, output_rate | nonnegative decimal strings, ≤9 fractional places; USD per million tokens |
| occurred_at, rate_effective_from, rate_verified_at | ISO-8601 timestamp strings with explicit timezone, ≤6 fractional digits, UTC year 2000–2099 |
| rate_effective_until | same timestamp type or null; half-open interval covers occurred_at |
| rate_source_url | provenance string, ≤2048 bytes; synthetic URN allowed |
| tool | normalized tool identifier |
| agent_run_id, workflow_type | normalized opaque identifier string or null |

No JSON monetary numbers, exponent notation, signed/NaN/infinite amounts, or more than 20 integer digits. Identifiers obey the corresponding canonical v1 format. Other text is bounded to 200 bytes. Body limit 64 KiB. Rails validates references, shape, interval, and `amount = input_cost + cached_input_cost + output_cost`; it never recalculates token prices. Service authentication trusts Kotlin's pricing authority.

Fingerprint: normalize UUIDs lowercase, decimal strings to plain minimal scale, timestamps to UTC with exactly six fractional digits; sort flat object keys lexicographically; UTF-8 JSON SHA-256. Both services apply the same rule. All original immutable identifiers and provenance remain in the receipt.

## Responses and idempotency

Posted response (201 for first post, 200 for matching repeat):

```json
{"schema_version":1,"priced_event_id":"SNAPSHOT-UUID","usage_event_id":"CANONICAL-UUID","status":"posted","amount":"0.1065","currency":"USD","financial_transaction_id":"ORIGINAL-CHARGE-UUID","code":null,"duplicate":false}
```

UUID placeholders above must be full UUIDs in real requests. A matching duplicate has `duplicate:true` and the same transaction ID. An unresolved owner returns 202 with status `unresolved`, null financial_transaction_id and actionable code such as `NO_FUNDED_CHARGE_OWNER` or `PROJECT_HISTORY_UNRESOLVED`. It is not an acknowledgement of a financial post. Replay after repair attempts resolution again. A correction never changes the original acknowledgement.

401: absent/invalid write credential. 409: UUID/source/fingerprint conflict. 422: invalid contract or tenant references. 503: temporary financial store failure. Error envelope: `{"error":{"code":"...","message":"..."}}`. No browser identity/header grants internal access.

## Sender delivery

Pricing snapshot and immutable outbox payload commit atomically. Claim uses PostgreSQL SKIP LOCKED and a 60-second tokenized lease. Workers are bounded (1–8); each claims at most four requests per worker. A lease holder must still own its token to update delivery state. Attempts are durable and total attempt numbers never reset.

Only 200/201 with matching schema/version, posted state, usage/snapshot IDs, exact decimal-string amount/USD and a valid transaction UUID counts as delivered. 202, network failures, malformed success, 408, 429 and 5xx retry with 5,10,20,40,80,160,300-second bounded backoff; eight attempts per cycle reach dead state. 401/403, 409 and permanent validation errors are explicit dead categories. `deliver --retry-dead true` starts a new bounded cycle while preserving attempts/payload. A crash after Rails commits can cause a repeat request, which returns the original post. No Kafka, Redis, automatic daemon, or exactly-once transport claim is needed.

## Read-only reconciliation

Request `{"priced_event_ids":["FULL-UUID"]}` accepts 1–100 UUIDs. Response root is `schema_version:1`, `data`, and `integrity`. Each data row reports priced_event_id/status, or `missing`; known rows also include usage_event_id, posted_usage_event_id, code, payload_fingerprint, financial_transaction_id and decimal strings original_amount, original_ledger_amount, net_amount, adjustment_delta. These distinguish original expense integrity from linked corrections.

Integrity counters: duplicate_expenses, unbalanced_transfers, posted_receipts_missing_transactions, invalid_operation_entries. Kotlin rejects malformed/incomplete replies and compares the original snapshot/ledger/fingerprint/acknowledgement independently of correction deltas. This contract requires no cross-schema privileges.
