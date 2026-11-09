# Usage event CSV contract — v1

One row describes one metered token-usage event. This is an internal, synthetic-data format; no live provider catalogue, prices, prompt text, completions, or financial authority is implied. Only `schema_version=1` is accepted.

Files use UTF-8 (optional BOM), RFC 4180 CSV quoting, comma delimiters, a single header record, and LF or CRLF separators. Quoted commas, escaped quotes, and multiline fields parse correctly; their decoded values must still satisfy field rules. Header names are exact, case-sensitive, unique, and may be reordered. Every required header must appear, even when `project_id` values are empty. Optional headers may be omitted. Unknown columns, including arbitrary metadata/prompt fields, fail the file rather than being silently discarded.

| Field | Required header/value | Meaning and bounds |
| --- | --- | --- |
| `schema_version` | Yes/yes | Literal `1`; unknown versions are row rejections |
| `event_id` | Yes/yes | Source's stable event ID, 1–128 ASCII characters; `[A-Za-z0-9][A-Za-z0-9._:/-]*` |
| `organization_id` | Yes/yes | Full hyphenated UUID; Rails-owned organization |
| `user_id` | Yes/yes | Full hyphenated UUID; current eligible user in that organization |
| `project_id` | Yes/no | Empty means unassigned; otherwise same-tenant project UUID with a recorded membership covering event time |
| `provider` | Yes/yes | Identifier, 1–64 characters; lowercase `[a-z0-9][a-z0-9._-]*` after canonicalization |
| `model` | Yes/yes | Provider-specific identifier, 1–200 ASCII characters; `[A-Za-z0-9][A-Za-z0-9._:/@+-]*`; case retained |
| `tool` | Yes/yes | Workflow/application identifier, 1–128 characters; lowercase `[a-z0-9][a-z0-9._-]*` |
| `input_tokens` | Yes/yes | Decimal integer, 0–1,000,000,000,000 |
| `output_tokens` | Yes/yes | Decimal integer, 0–1,000,000,000,000 |
| `occurred_at` | Yes/yes | ISO 8601 timestamp with explicit `Z` or numeric offset; UTC year 2000–2099 |
| `cached_input_tokens` | No/no | Default zero; nonnegative integer no greater than input_tokens, a subset of input rather than extra usage |
| `agent_run_id` | No/no | Optional identifier with event_id's pattern and 128-character maximum |
| `workflow_type` | No/no | Optional lowercase identifier with provider's pattern and 64-character maximum |

Surrounding value whitespace is trimmed. UUIDs normalize to lowercase. Provider/tool/workflow identifiers lowercase using Locale.ROOT; no aliases or provider/model mappings are guessed. Model and event/agent identifier case is retained. At least one input/output token must be positive. Numeric signs, fractions, exponential notation, and overflow are rejected. Leading zeroes normalize through integer parsing. The trillion-token ceiling fits BIGINT safely while allowing very large legitimate workloads; it is a data bound, not a pricing limit. Decoded field values have an additional 512-character ceiling.

Times normalize to UTC and truncate sub-microsecond precision to match PostgreSQL timestamptz. Explicit synthetic future times are allowed within the year bounds; current time is not used as a nondeterministic validation cutoff. File limits are 20 MiB and 100,000 data records. Record numbers are logical CSV records: header is 1, first data record is 2, even when a quoted field spans physical lines.

The stable source namespace is **import-level metadata**, required as `--source demo-synthetic-v1`. It is 1–64 lowercase ASCII identifier characters with the provider pattern. Do not use filenames, timestamps, or batch UUIDs as sources. Namespaces are trusted local operator inputs; there is no public upload endpoint.

Example with illustrative UUIDs (real imports use exported Rails references):

```csv
schema_version,event_id,organization_id,user_id,project_id,provider,model,tool,input_tokens,output_tokens,occurred_at,agent_run_id
1,evt-000001,11111111-1111-1111-1111-111111111111,22222222-2222-2222-2222-222222222222,,openai,demo-code-v1,coding-assistant,12500,4200,2026-11-10T14:30:00Z,run-001
```

## Reference policy: membership-period-v1

The backend-only Rails contract validates bounded batches. Organizations must exist. Users must exist in that tenant and be **currently active**. Historical employment/status is not modeled; this policy does not certify past employment and deliberately rejects currently inactive users rather than guessing their past status. There is no home-team/project-ownership requirement.

A project must exist in the same organization. A recorded membership must satisfy `joined_at <= occurred_at < left_at`, with null left_at meaning open-ended. Removed participants can therefore submit valid historical events, and gaps between periods stay invalid. Archived/planned projects remain referenceable when a recorded membership covers the timestamp: archive/status history is unavailable, so current status is not used to infer event-time status. Events earlier than the first recorded membership are rejected as `PROJECT_MEMBERSHIP_NOT_ESTABLISHED`. Unassigned project usage needs no membership.

Current references are revalidated on imports, including replay attempts. Exact reference results are cached only inside an import (up to 4,096 entries); event time is part of the key. Rails unavailability/authentication/protocol failure is infrastructure failure, never evidence of an unknown user. The reference check is a point-in-time decision, not a distributed transaction or permanent foreign key into business data.

## Idempotency and immutable events

PostgreSQL enforces `(organization_id, source, event_id)` uniqueness. Identical canonical replay counts as a duplicate. A different canonical payload under that key is rejected with `EVENT_ID_CONFLICT`; the original row, original batch attribution, tokens, and references remain unchanged. Invalid field/reference records are rejected before insertion/deduplication; they do not reserve identities. Within-file, cross-file, and concurrent duplicates use the same database conflict handling.

The SHA-256 fingerprint includes schema version, organization, source, event ID, user, optional project, canonical provider/model/tool, input/output/cached tokens, UTC microsecond time, optional agent run, and workflow type, in that order. Each field is UTF-8 length-prefixed (`byte_length:value`), with `-1:` for null. Filenames, row order, batch IDs, and import time are excluded. Optional blanks normalize to null, except cached tokens normalize to zero.

## Errors, partial imports, and counts

Each row rejection stores batch ID, logical row number, safe event ID if validly formatted, stable code, field, and a fixed explanation. No raw row, arbitrary metadata, prompt/completion content, remote response text, stack trace, or credential is persisted in rejection records.

Common row codes: `REQUIRED_VALUE`, `UNSUPPORTED_SCHEMA_VERSION`, `INVALID_UUID`, `INVALID_TIMESTAMP`, `INVALID_TOKEN_COUNT`, `ZERO_TOKEN_EVENT`, `INVALID_CACHED_TOKENS`, `INVALID_IDENTIFIER`, `FIELD_TOO_LONG`, `COLUMN_COUNT`, `UNKNOWN_ORGANIZATION`, `INVALID_USER_REFERENCE`, `USER_INELIGIBLE`, `INVALID_PROJECT_REFERENCE`, `PROJECT_MEMBERSHIP_NOT_ESTABLISHED`, `EVENT_ID_CONFLICT`.

File-level errors include `EMPTY_FILE`, `EMPTY_DATASET`, `INVALID_HEADERS`, `UNSUPPORTED_COLUMNS`, `INVALID_UTF8`, `INVALID_CSV`, `FILE_TOO_LARGE`, `ROW_LIMIT_EXCEEDED`, and `FILE_UNREADABLE`. Header errors use row 1. A column-count mismatch rejects that record and continues. Malformed quoting cannot be safely resynchronized: complete preceding buffered records are committed, a file error is recorded, and scanning stops. An unterminated record is not counted as a parsed data row; later input is not claimed as processed.

Reference failures use `REFERENCE_SERVICE_UNAVAILABLE`, `REFERENCE_SERVICE_AUTHORIZATION`, `REFERENCE_SERVICE_CONFIGURATION`, or `REFERENCE_PROTOCOL_ERROR`. Persistence errors use `DATABASE_PERSISTENCE_FAILURE` (with batch ID in the CLI failure when finalization cannot be written). Unexpected processing failure uses `IMPORT_EXECUTION_FAILURE`. These are retryable infrastructure categories; valid records already committed remain stored.

| Report field | Meaning |
| --- | --- |
| `totalRows` | Complete parsed data records observed, including recoverable malformed-column rows; excludes header and an unparseable quoting fragment |
| `acceptedRows` | Newly inserted immutable events, committed atomically with batch counts |
| `duplicateRows` | Canonically identical existing events |
| `rejectedRows` | Parsed data rows rejected by field/reference/conflict validation |
| `unprocessedRows` | Observed rows without a committed outcome after infrastructure interruption |
| `infrastructureFailures` | Failed infrastructure operations/abandonment detected, not invalid-row count |
| `scanComplete` | Whether input scanning reached EOF; a failure may leave unread input whose size is unknown |
| `durationMillis` | Start-to-completion duration, available for finalized batches |

A file-level diagnostic is stored among rejection details but does not increment rejectedRows, which counts data-row outcomes. Therefore rejection-detail count may differ from rejectedRows. `totalRows >= acceptedRows + duplicateRows + rejectedRows`; equality holds on completed imports. Sources and files may contain multiple tenants, but each row must independently satisfy Rails validation.

Statuses: `running`, `completed`, `completed_with_rejections`, `partial` (fatal error after committed row outcomes), `failed` (fatal error with no committed outcomes). Chunks contain at most 250 rows by default (hard service maximum 500). A chunk's event/rejection writes and count updates share one database transaction; imports do not use one unbounded transaction.

Caught failures finalize metadata where the database is available. If PostgreSQL is down or a process is killed, reports/import startup reconcile `running` batches with heartbeats older than fifteen minutes as partial/failed `IMPORT_INTERRUPTED`. Until then, `running` means active or not yet known to be interrupted. Transactions lock/check the batch status before writing, so a reconciled worker cannot resume committing. An interruption during a lost connection can have an ambiguous commit acknowledgment; retry resolves it through immutable identity keys. No claim is made about unread or uncommitted observed rows after an abrupt process death.

CLI exit codes: **0** successful import (duplicates included), report/list/snapshot/generation; **2** completed import with row rejections; **3** fatal/partial import or infrastructure failure; **64** invalid CLI arguments. Reports return 0 when read successfully even when the reported batch failed. Rejections are paginated at up to 100; use `report BATCH_UUID --offset 100 --limit 100` to inspect further details. The CLI error summary includes all rejection codes/counts.
