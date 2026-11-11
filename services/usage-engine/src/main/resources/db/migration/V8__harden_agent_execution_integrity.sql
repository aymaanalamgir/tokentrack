ALTER TABLE usage.agent_definitions
  ADD CONSTRAINT agent_definitions_fingerprint_format CHECK (fingerprint ~ '^[0-9a-f]{64}$'),
  ADD CONSTRAINT agent_definitions_workflow_format CHECK (workflow_type ~ '^[a-z0-9][a-z0-9._-]{0,63}$');

ALTER TABLE usage.agent_runs
  ADD CONSTRAINT agent_runs_source_format CHECK (source ~ '^[A-Za-z0-9][A-Za-z0-9._:-]{0,63}$'),
  ADD CONSTRAINT agent_runs_external_id_format CHECK (external_run_id ~ '^[A-Za-z0-9][A-Za-z0-9._:/-]{0,127}$'),
  ADD CONSTRAINT agent_runs_fingerprint_format CHECK (fingerprint ~ '^[0-9a-f]{64}$');

ALTER TABLE usage.agent_attempts
  ADD CONSTRAINT agent_attempts_external_id_format CHECK (external_attempt_id ~ '^[A-Za-z0-9][A-Za-z0-9._:/-]{0,127}$'),
  ADD CONSTRAINT agent_attempts_fingerprint_format CHECK (fingerprint ~ '^[0-9a-f]{64}$');

ALTER TABLE usage.agent_import_batches
  ADD CONSTRAINT agent_import_batches_source_format CHECK (source ~ '^[A-Za-z0-9][A-Za-z0-9._:-]{0,63}$'),
  ADD CONSTRAINT agent_import_batches_status CHECK (status IN ('running','completed','completed_with_rejections','failed')),
  ADD CONSTRAINT agent_import_batches_counts CHECK (total_rows >= 0 AND imported_rows >= 0 AND duplicate_rows >= 0 AND rejected_rows >= 0 AND unlinked_rows >= 0 AND imported_rows + duplicate_rows + rejected_rows <= total_rows),
  ADD CONSTRAINT agent_import_batches_completion CHECK ((status='running' AND completed_at IS NULL) OR (status<>'running' AND completed_at IS NOT NULL));

ALTER TABLE usage.agent_import_rejections
  ADD CONSTRAINT agent_import_rejections_line CHECK (line_number > 0),
  ADD CONSTRAINT agent_import_rejections_code_format CHECK (code ~ '^[A-Z][A-Z0-9_]{0,63}$'),
  ADD CONSTRAINT agent_import_rejections_field_format CHECK (field ~ '^[a-z][a-z0-9_]{0,63}$');
