class CreateFinancialRequests < ActiveRecord::Migration[8.1]
  def up
    create_table :financial_requests, id: :uuid do |t|
      t.uuid :organization_id, null: false
      t.uuid :requester_id, null: false
      t.string :request_type, null: false
      t.uuid :target_user_id
      t.uuid :target_project_id
      t.uuid :target_unit_id
      t.uuid :target_budget_account_id
      t.uuid :source_budget_account_id
      t.date :month_start, null: false
      t.string :currency, null: false, default: "USD"
      t.decimal :current_amount_snapshot, precision: 38, scale: 15, null: false
      t.decimal :source_available_snapshot, precision: 38, scale: 15
      t.decimal :requested_amount, precision: 38, scale: 15, null: false
      t.uuid :allowance_revision_snapshot_id
      t.string :reason, null: false, limit: 500
      t.string :status, null: false, default: "pending"
      t.uuid :assigned_approver_id
      t.string :routing_reason, null: false, limit: 500
      t.string :request_key, null: false, limit: 128
      t.string :request_fingerprint, null: false, limit: 64
      t.uuid :execution_transaction_id
      t.uuid :execution_revision_id
      t.datetime :submitted_at, null: false, default: -> { "CURRENT_TIMESTAMP" }
      t.datetime :resolved_at
      t.datetime :escalated_at
      t.integer :lock_version, null: false, default: 0
      t.timestamps
    end

    create_table :request_events, id: :uuid do |t|
      t.uuid :organization_id, null: false
      t.uuid :financial_request_id, null: false
      t.uuid :actor_id, null: false
      t.string :event_type, null: false
      t.string :previous_status
      t.string :new_status
      t.string :reason, null: false, limit: 500
      t.string :operation_key, null: false, limit: 128
      t.string :operation_fingerprint, null: false, limit: 64
      t.jsonb :metadata, null: false, default: {}
      t.datetime :created_at, null: false, default: -> { "CURRENT_TIMESTAMP" }
    end

    %i[financial_requests request_events].each do |table|
      add_index table, [:organization_id, :id], unique: true
      add_foreign_key table, :organizations
    end
    add_index :financial_requests, [:organization_id, :requester_id, :request_key], unique: true, name: "idempotent_financial_request"
    add_index :financial_requests, [:organization_id, :status, :assigned_approver_id, :submitted_at], name: "financial_request_inbox"
    add_index :financial_requests, [:organization_id, :requester_id, :submitted_at], name: "financial_request_requester_history"
    add_index :financial_requests, [:organization_id, :month_start, :request_type]
    add_index :request_events, [:financial_request_id, :operation_key], unique: true, name: "idempotent_request_event"
    add_index :request_events, [:organization_id, :actor_id, :created_at]
    add_index :request_events, [:financial_request_id, :created_at]

    fk :financial_requests, :users, :requester_id
    fk :financial_requests, :users, :target_user_id
    fk :financial_requests, :users, :assigned_approver_id
    fk :financial_requests, :projects, :target_project_id
    fk :financial_requests, :organizational_units, :target_unit_id
    fk :financial_requests, :budget_accounts, :target_budget_account_id
    fk :financial_requests, :budget_accounts, :source_budget_account_id
    fk :financial_requests, :spending_limit_revisions, :allowance_revision_snapshot_id
    fk :financial_requests, :financial_transactions, :execution_transaction_id
    fk :financial_requests, :spending_limit_revisions, :execution_revision_id
    fk :request_events, :financial_requests, :financial_request_id
    fk :request_events, :users, :actor_id

    execute <<~SQL
      ALTER TABLE business.financial_requests ADD CONSTRAINT valid_financial_request CHECK (
        currency='USD' AND status IN ('pending','approved','rejected','cancelled')
        AND request_type IN ('personal_allowance','project_funding','team_funding')
        AND requested_amount>0 AND requested_amount<'Infinity'::numeric
        AND current_amount_snapshot>=0 AND current_amount_snapshot<'Infinity'::numeric
        AND (source_available_snapshot IS NULL OR (source_available_snapshot>=0 AND source_available_snapshot<'Infinity'::numeric))
        AND EXTRACT(DAY FROM month_start)=1 AND month_start BETWEEN '2000-01-01' AND '2099-12-01'
        AND length(reason)>0 AND length(routing_reason)>0
        AND ((status='pending' AND resolved_at IS NULL) OR (status<>'pending' AND resolved_at IS NOT NULL))
        AND (
          (request_type='personal_allowance' AND target_user_id IS NOT NULL AND target_project_id IS NULL AND target_unit_id IS NULL AND target_budget_account_id IS NULL AND source_budget_account_id IS NULL AND source_available_snapshot IS NULL AND allowance_revision_snapshot_id IS NOT NULL AND requested_amount>current_amount_snapshot)
          OR
          (request_type='project_funding' AND target_user_id IS NULL AND target_project_id IS NOT NULL AND target_unit_id IS NULL AND target_budget_account_id IS NOT NULL AND source_budget_account_id IS NOT NULL AND source_available_snapshot IS NOT NULL AND allowance_revision_snapshot_id IS NULL)
          OR
          (request_type='team_funding' AND target_user_id IS NULL AND target_project_id IS NULL AND target_unit_id IS NOT NULL AND target_budget_account_id IS NOT NULL AND source_budget_account_id IS NOT NULL AND source_available_snapshot IS NOT NULL AND allowance_revision_snapshot_id IS NULL)
        )
      );
      ALTER TABLE business.request_events ADD CONSTRAINT valid_request_event CHECK (
        event_type IN ('created','submitted','escalated','approved','rejected','cancelled','executed')
        AND (previous_status IS NULL OR previous_status IN ('pending','approved','rejected','cancelled'))
        AND (new_status IS NULL OR new_status IN ('pending','approved','rejected','cancelled'))
        AND length(reason)>0
      );

      CREATE FUNCTION business.guard_financial_request() RETURNS trigger LANGUAGE plpgsql AS $$
      BEGIN
        IF TG_OP IN ('DELETE','TRUNCATE') THEN RAISE EXCEPTION 'Request history is append-only' USING ERRCODE='23514'; END IF;
        IF OLD.organization_id<>NEW.organization_id OR OLD.requester_id<>NEW.requester_id OR OLD.request_type<>NEW.request_type OR OLD.request_key<>NEW.request_key OR OLD.created_at<>NEW.created_at THEN
          RAISE EXCEPTION 'Request identity is immutable' USING ERRCODE='23514'; END IF;
        IF OLD.status<>'pending' THEN RAISE EXCEPTION 'A finalized request is immutable' USING ERRCODE='23514'; END IF;
        IF OLD.target_user_id IS DISTINCT FROM NEW.target_user_id OR OLD.target_project_id IS DISTINCT FROM NEW.target_project_id OR OLD.target_unit_id IS DISTINCT FROM NEW.target_unit_id OR OLD.target_budget_account_id IS DISTINCT FROM NEW.target_budget_account_id OR OLD.source_budget_account_id IS DISTINCT FROM NEW.source_budget_account_id OR OLD.month_start<>NEW.month_start OR OLD.currency<>NEW.currency OR OLD.current_amount_snapshot<>NEW.current_amount_snapshot OR OLD.source_available_snapshot IS DISTINCT FROM NEW.source_available_snapshot OR OLD.requested_amount<>NEW.requested_amount OR OLD.allowance_revision_snapshot_id IS DISTINCT FROM NEW.allowance_revision_snapshot_id OR OLD.reason<>NEW.reason OR OLD.submitted_at<>NEW.submitted_at OR OLD.request_fingerprint<>NEW.request_fingerprint THEN
          RAISE EXCEPTION 'Submitted request terms are immutable' USING ERRCODE='23514'; END IF;
        RETURN NEW;
      END $$;
      CREATE FUNCTION business.guard_request_event() RETURNS trigger LANGUAGE plpgsql AS $$
      BEGIN RAISE EXCEPTION 'Request events are append-only' USING ERRCODE='23514'; END $$;
      CREATE TRIGGER financial_requests_guard BEFORE UPDATE OR DELETE ON business.financial_requests FOR EACH ROW EXECUTE FUNCTION business.guard_financial_request();
      CREATE TRIGGER financial_requests_no_truncate BEFORE TRUNCATE ON business.financial_requests FOR EACH STATEMENT EXECUTE FUNCTION business.guard_financial_request();
      CREATE TRIGGER request_events_immutable BEFORE UPDATE OR DELETE ON business.request_events FOR EACH ROW EXECUTE FUNCTION business.guard_request_event();
      CREATE TRIGGER request_events_no_truncate BEFORE TRUNCATE ON business.request_events FOR EACH STATEMENT EXECUTE FUNCTION business.guard_request_event();
    SQL
  end

  def down
    raise ActiveRecord::IrreversibleMigration, "Preserve request and decision history"
  end

  private

  def fk(from, to, column)
    execute "ALTER TABLE business.#{from} ADD FOREIGN KEY(organization_id,#{column}) REFERENCES business.#{to}(organization_id,id)"
  end
end
