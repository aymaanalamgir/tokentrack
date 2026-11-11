# Agent execution JSONL v1

Agent execution is a separate append-only sidecar contract. It does not change usage CSV v1, its optional `agent_run_id` / `workflow_type` fields, or any existing usage fingerprint.

Each UTF-8 JSONL line is one complete run. Imports require `--source`; every line must contain that exact source. Unknown or missing fields are rejected. Files are bounded to 20 MB, lines to 256 KB, and runs to 100 attempts.

```json
{"schema_version":1,"source":"demo-synthetic-v1","organization_id":"00000000-0000-0000-0000-000000000000","run_id":"run-123","agent":{"key":"code-review-acde1234","name":"Code Review","description":"Reviews pull requests","workflow_type":"code-review","owner_user_id":"00000000-0000-0000-0000-000000000001","project_id":"00000000-0000-0000-0000-000000000002","status":"active"},"user_id":"00000000-0000-0000-0000-000000000001","project_id":"00000000-0000-0000-0000-000000000002","started_at":"2026-11-10T15:00:00Z","completed_at":"2026-11-10T15:00:42Z","status":"completed","outcome":"success","outcome_source":"observed","attempts":[{"attempt_id":"run-123-a1","attempt_number":1,"started_at":"2026-11-10T15:00:00Z","completed_at":"2026-11-10T15:00:42Z","status":"succeeded","error_category":null}]}
```

Identity is `(organization_id, source, run_id)`. Agent definition identity is `(organization_id, source, agent.key)`. Attempts are numbered contiguously from 1 and have unique IDs within a run. Exact replay is a duplicate; changed content under an existing identity is `IDENTITY_CONFLICT`. Stored definitions, runs, and attempts are immutable.

| run status | outcome | completed_at |
| --- | --- | --- |
| `running` | `unknown` | null |
| `completed` | `success` | required |
| `failed` | `failure` | required |
| `cancelled` | `cancelled` | required |

Attempt states are `running`, `succeeded`, `failed`, and `cancelled`. Failed attempts require `timeout`, `provider_error`, `validation_failure`, `tool_execution_error`, or `unknown_failure`. Running attempts have no completion/error; successful/cancelled attempts have completion and no error. Rails validates organization/user/project membership at run start.

Usage linkage is read-only and exact: `organization_id + source + run_id = usage_events.organization_id + source + agent_run_id`. A run may have zero or many usage events; zero is reported as unlinked and does not mutate usage or the financial ledger.
