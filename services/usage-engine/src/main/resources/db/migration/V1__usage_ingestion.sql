CREATE TABLE usage.import_batches (
  id uuid PRIMARY KEY,
  source varchar(64) NOT NULL CHECK (source ~ '^[a-z0-9][a-z0-9._-]{0,63}$'),
  input_label varchar(120) NOT NULL,
  schema_version integer NOT NULL DEFAULT 1 CHECK (schema_version = 1),
  status varchar(32) NOT NULL CHECK (status IN ('running','completed','completed_with_rejections','partial','failed')),
  started_at timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP,
  heartbeat_at timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP,
  completed_at timestamptz,
  total_rows integer NOT NULL DEFAULT 0 CHECK (total_rows >= 0),
  accepted_rows integer NOT NULL DEFAULT 0 CHECK (accepted_rows >= 0),
  duplicate_rows integer NOT NULL DEFAULT 0 CHECK (duplicate_rows >= 0),
  rejected_rows integer NOT NULL DEFAULT 0 CHECK (rejected_rows >= 0),
  infrastructure_failures integer NOT NULL DEFAULT 0 CHECK (infrastructure_failures >= 0),
  scan_complete boolean NOT NULL DEFAULT false,
  failure_code varchar(64),
  CHECK (accepted_rows + duplicate_rows + rejected_rows <= total_rows),
  CHECK ((status = 'running' AND completed_at IS NULL) OR (status <> 'running' AND completed_at IS NOT NULL))
);
CREATE INDEX import_batches_started ON usage.import_batches (started_at DESC);
CREATE TABLE usage.usage_events (
  id uuid PRIMARY KEY,
  organization_id uuid NOT NULL,
  source varchar(64) NOT NULL,
  event_id varchar(128) NOT NULL CHECK (event_id ~ '^[A-Za-z0-9][A-Za-z0-9._:/-]{0,127}$'),
  user_id uuid NOT NULL,
  project_id uuid,
  provider varchar(64) NOT NULL CHECK (provider ~ '^[a-z0-9][a-z0-9._-]{0,63}$'),
  model varchar(200) NOT NULL CHECK (model ~ '^[A-Za-z0-9][A-Za-z0-9._:/@+-]{0,199}$'),
  tool varchar(128) NOT NULL CHECK (tool ~ '^[a-z0-9][a-z0-9._-]{0,127}$'),
  input_tokens bigint NOT NULL CHECK (input_tokens BETWEEN 0 AND 1000000000000),
  output_tokens bigint NOT NULL CHECK (output_tokens BETWEEN 0 AND 1000000000000),
  cached_input_tokens bigint NOT NULL DEFAULT 0 CHECK (cached_input_tokens >= 0 AND cached_input_tokens <= input_tokens),
  occurred_at timestamptz NOT NULL CHECK (occurred_at >= '2000-01-01T00:00:00Z' AND occurred_at < '2100-01-01T00:00:00Z'),
  agent_run_id varchar(128),
  workflow_type varchar(64),
  import_batch_id uuid NOT NULL REFERENCES usage.import_batches(id) ON DELETE RESTRICT,
  schema_version integer NOT NULL CHECK (schema_version = 1),
  payload_fingerprint char(64) NOT NULL CHECK (payload_fingerprint ~ '^[0-9a-f]{64}$'),
  created_at timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP,
  CHECK (input_tokens + output_tokens > 0),
  CHECK (source ~ '^[a-z0-9][a-z0-9._-]{0,63}$'),
  CHECK (agent_run_id IS NULL OR agent_run_id ~ '^[A-Za-z0-9][A-Za-z0-9._:/-]{0,127}$'),
  CHECK (workflow_type IS NULL OR workflow_type ~ '^[a-z0-9][a-z0-9._-]{0,63}$'),
  CONSTRAINT unique_source_event UNIQUE (organization_id, source, event_id)
);
CREATE INDEX usage_events_organization_time ON usage.usage_events (organization_id, occurred_at);
CREATE INDEX usage_events_user_time ON usage.usage_events (organization_id, user_id, occurred_at);
CREATE INDEX usage_events_project_time ON usage.usage_events (organization_id, project_id, occurred_at) WHERE project_id IS NOT NULL;
CREATE INDEX usage_events_batch ON usage.usage_events (import_batch_id);
CREATE TABLE usage.import_rejections (
  id uuid PRIMARY KEY,
  import_batch_id uuid NOT NULL REFERENCES usage.import_batches(id) ON DELETE RESTRICT,
  row_number integer NOT NULL CHECK (row_number >= 1),
  event_id varchar(128),
  code varchar(64) NOT NULL,
  field varchar(64) NOT NULL,
  message varchar(300) NOT NULL,
  created_at timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP
);
CREATE INDEX import_rejections_batch_row ON usage.import_rejections (import_batch_id, row_number);
