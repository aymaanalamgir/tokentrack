CREATE TABLE usage.agent_definitions (
  id uuid PRIMARY KEY,
  organization_id uuid NOT NULL,
  source varchar(64) NOT NULL,
  agent_key varchar(128) NOT NULL,
  name varchar(160) NOT NULL,
  description varchar(1000),
  workflow_type varchar(64) NOT NULL,
  owner_user_id uuid NOT NULL,
  project_id uuid,
  status varchar(16) NOT NULL CHECK (status IN ('active','inactive')),
  fingerprint char(64) NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE (organization_id, source, agent_key),
  UNIQUE (organization_id, id),
  CHECK (source ~ '^[A-Za-z0-9][A-Za-z0-9._:-]{0,63}$'),
  CHECK (agent_key ~ '^[A-Za-z0-9][A-Za-z0-9._:-]{0,127}$')
);

CREATE TABLE usage.agent_runs (
  id uuid PRIMARY KEY,
  organization_id uuid NOT NULL,
  agent_definition_id uuid NOT NULL,
  source varchar(64) NOT NULL,
  external_run_id varchar(128) NOT NULL,
  user_id uuid NOT NULL,
  project_id uuid,
  started_at timestamptz NOT NULL,
  completed_at timestamptz,
  status varchar(16) NOT NULL CHECK (status IN ('running','completed','failed','cancelled')),
  outcome varchar(16) NOT NULL CHECK (outcome IN ('success','failure','cancelled','unknown')),
  outcome_source varchar(32) NOT NULL CHECK (outcome_source IN ('observed','synthetic_fixture')),
  fingerprint char(64) NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE (organization_id, source, external_run_id),
  UNIQUE (organization_id, id),
  FOREIGN KEY (organization_id, agent_definition_id) REFERENCES usage.agent_definitions(organization_id, id),
  CHECK (completed_at IS NULL OR completed_at >= started_at),
  CHECK ((status='running' AND completed_at IS NULL AND outcome='unknown') OR
         (status='completed' AND completed_at IS NOT NULL AND outcome='success') OR
         (status='failed' AND completed_at IS NOT NULL AND outcome='failure') OR
         (status='cancelled' AND completed_at IS NOT NULL AND outcome='cancelled'))
);

CREATE TABLE usage.agent_attempts (
  id uuid PRIMARY KEY,
  organization_id uuid NOT NULL,
  agent_run_id uuid NOT NULL,
  external_attempt_id varchar(128) NOT NULL,
  attempt_number integer NOT NULL CHECK (attempt_number > 0 AND attempt_number <= 100),
  started_at timestamptz NOT NULL,
  completed_at timestamptz,
  status varchar(16) NOT NULL CHECK (status IN ('running','succeeded','failed','cancelled')),
  error_category varchar(32) CHECK (error_category IN ('timeout','provider_error','validation_failure','tool_execution_error','unknown_failure')),
  fingerprint char(64) NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now(),
  FOREIGN KEY (organization_id, agent_run_id) REFERENCES usage.agent_runs(organization_id, id),
  UNIQUE (agent_run_id, attempt_number),
  UNIQUE (agent_run_id, external_attempt_id),
  CHECK (completed_at IS NULL OR completed_at >= started_at),
  CHECK ((status='running' AND completed_at IS NULL AND error_category IS NULL) OR
         (status='failed' AND completed_at IS NOT NULL AND error_category IS NOT NULL) OR
         (status IN ('succeeded','cancelled') AND completed_at IS NOT NULL AND error_category IS NULL))
);

CREATE TABLE usage.agent_import_batches (
  id uuid PRIMARY KEY,
  source varchar(64) NOT NULL,
  input_label varchar(255) NOT NULL,
  status varchar(32) NOT NULL,
  total_rows integer NOT NULL DEFAULT 0,
  imported_rows integer NOT NULL DEFAULT 0,
  duplicate_rows integer NOT NULL DEFAULT 0,
  rejected_rows integer NOT NULL DEFAULT 0,
  unlinked_rows integer NOT NULL DEFAULT 0,
  started_at timestamptz NOT NULL DEFAULT now(),
  completed_at timestamptz,
  failure_code varchar(64)
);

CREATE TABLE usage.agent_import_rejections (
  id bigserial PRIMARY KEY,
  batch_id uuid NOT NULL REFERENCES usage.agent_import_batches(id),
  line_number integer NOT NULL,
  code varchar(64) NOT NULL,
  field varchar(64) NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX agent_runs_scope_idx ON usage.agent_runs(organization_id, started_at DESC, agent_definition_id);
CREATE INDEX agent_runs_user_idx ON usage.agent_runs(organization_id, user_id, started_at DESC);
CREATE INDEX agent_runs_project_idx ON usage.agent_runs(organization_id, project_id, started_at DESC);
CREATE INDEX agent_attempts_run_idx ON usage.agent_attempts(agent_run_id, attempt_number);
CREATE INDEX usage_events_agent_link_idx ON usage.usage_events(organization_id, source, agent_run_id) WHERE agent_run_id IS NOT NULL;

CREATE OR REPLACE FUNCTION usage.reject_agent_execution_mutation() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN RAISE EXCEPTION 'agent execution records are append-only'; END $$;
CREATE TRIGGER agent_definitions_append_only BEFORE UPDATE OR DELETE ON usage.agent_definitions FOR EACH ROW EXECUTE FUNCTION usage.reject_agent_execution_mutation();
CREATE TRIGGER agent_runs_append_only BEFORE UPDATE OR DELETE ON usage.agent_runs FOR EACH ROW EXECUTE FUNCTION usage.reject_agent_execution_mutation();
CREATE TRIGGER agent_attempts_append_only BEFORE UPDATE OR DELETE ON usage.agent_attempts FOR EACH ROW EXECUTE FUNCTION usage.reject_agent_execution_mutation();
