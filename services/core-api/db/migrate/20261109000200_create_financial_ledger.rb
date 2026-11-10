class CreateFinancialLedger < ActiveRecord::Migration[8.1]
  def up
    remove_check_constraint :role_assignments, name: "valid_role_and_explicit_scope"
    add_check_constraint :role_assignments, <<~SQL.squish, name: "valid_role_and_explicit_scope"
      (role='employee' AND scope_type='self' AND organizational_unit_id IS NULL AND project_id IS NULL) OR
      (role IN ('organization_viewer','project_creator','financial_operator') AND scope_type='organization' AND organizational_unit_id IS NULL AND project_id IS NULL) OR
      (role='team_manager' AND scope_type='unit' AND organizational_unit_id IS NOT NULL AND project_id IS NULL) OR
      (role='project_lead' AND scope_type='project' AND project_id IS NOT NULL AND organizational_unit_id IS NULL)
    SQL
    create_table :budget_accounts, id: :uuid do |t|
      t.uuid :organization_id, null: false
      t.string :name, null: false, limit: 120
      t.string :purpose, null: false
      t.uuid :organizational_unit_id
      t.uuid :project_id
      t.string :currency, null: false, default: "USD"
      t.string :status, null: false, default: "active"
      t.datetime :effective_from, null: false
      t.datetime :effective_until
      t.timestamps
    end
    create_table :budget_periods, id: :uuid do |t|
      t.uuid :organization_id, null: false
      t.uuid :budget_account_id, null: false
      t.date :month_start, null: false
      t.string :currency, null: false, default: "USD"
      t.string :status, null: false, default: "open"
      t.timestamps
    end
    create_table :priced_usage_receipts, id: :uuid do |t|
      t.uuid :organization_id, null: false
      t.uuid :usage_event_id, null: false
      t.uuid :user_id, null: false
      t.uuid :project_id
      t.datetime :occurred_at, null: false
      t.decimal :amount, precision: 38, scale: 15, null: false
      t.string :currency, null: false
      t.jsonb :payload, null: false
      t.string :payload_fingerprint, null: false, limit: 64
      t.string :status, null: false, default: "unresolved"
      t.string :resolution_code
      t.uuid :financial_transaction_id
      t.timestamps
    end
    create_table :financial_transactions, id: :uuid do |t|
      t.uuid :organization_id, null: false
      t.string :kind, null: false
      t.string :currency, null: false, default: "USD"
      t.date :month_start, null: false
      t.decimal :amount, precision: 38, scale: 15, null: false
      t.string :source_type, null: false, limit: 64
      t.string :source_id, null: false, limit: 128
      t.string :request_fingerprint, null: false, limit: 64
      t.uuid :actor_id
      t.uuid :priced_usage_receipt_id
      t.uuid :usage_event_id
      t.uuid :user_id
      t.uuid :project_id
      t.uuid :home_unit_id
      t.uuid :original_transaction_id
      t.uuid :correction_group_id
      t.string :reason, null: false, limit: 500
      t.jsonb :audit_metadata, null: false, default: {}
      t.bigint :write_transaction_id, null: false, default: -> { "txid_current()" }
      t.datetime :created_at, null: false, default: -> { "CURRENT_TIMESTAMP" }
    end
    create_table :ledger_entries, id: :uuid do |t|
      t.uuid :organization_id, null: false
      t.uuid :financial_transaction_id, null: false
      t.uuid :budget_period_id, null: false
      t.decimal :funding_delta, precision: 38, scale: 15, null: false, default: 0
      t.decimal :expense_delta, precision: 38, scale: 15, null: false, default: 0
      t.datetime :created_at, null: false, default: -> { "CURRENT_TIMESTAMP" }
    end
    %i[budget_accounts budget_periods priced_usage_receipts financial_transactions ledger_entries].each do |table|
      add_index table, [:organization_id, :id], unique: true
      add_foreign_key table, :organizations
    end
    tenant_fk :budget_accounts, :organizational_units, :organizational_unit_id
    tenant_fk :budget_accounts, :projects, :project_id
    tenant_fk :budget_periods, :budget_accounts, :budget_account_id
    tenant_fk :priced_usage_receipts, :users, :user_id
    tenant_fk :priced_usage_receipts, :projects, :project_id
    tenant_fk :priced_usage_receipts, :financial_transactions, :financial_transaction_id
    tenant_fk :financial_transactions, :users, :actor_id
    tenant_fk :financial_transactions, :users, :user_id
    tenant_fk :financial_transactions, :projects, :project_id
    tenant_fk :financial_transactions, :organizational_units, :home_unit_id
    tenant_fk :financial_transactions, :priced_usage_receipts, :priced_usage_receipt_id
    tenant_fk :financial_transactions, :financial_transactions, :original_transaction_id
    tenant_fk :ledger_entries, :financial_transactions, :financial_transaction_id
    tenant_fk :ledger_entries, :budget_periods, :budget_period_id
    add_index :budget_accounts, [:organization_id, :currency, :purpose], unique: true, where: "purpose IN ('reserve','unassigned')", name: "unique_organization_budget_purpose"
    add_index :budget_accounts, [:organization_id, :organizational_unit_id, :currency], unique: true, where: "purpose='unit'", name: "unique_unit_budget_account"
    add_index :budget_accounts, [:organization_id, :project_id, :currency], unique: true, where: "purpose='project'", name: "unique_project_budget_account"
    add_index :budget_periods, [:budget_account_id, :month_start], unique: true
    add_index :priced_usage_receipts, :usage_event_id, unique: true
    add_index :priced_usage_receipts, :status
    add_index :financial_transactions, [:organization_id, :source_type, :source_id], unique: true, name: "unique_financial_source"
    add_index :financial_transactions, :usage_event_id, unique: true, where: "kind='usage_charge'", name: "one_original_expense_per_usage"
    add_index :financial_transactions, :original_transaction_id, unique: true, where: "kind='reversal'", name: "one_reversal_per_operation"
    add_index :financial_transactions, :original_transaction_id
    add_index :ledger_entries, :budget_period_id
    add_check_constraint :budget_accounts, "currency='USD' AND status IN ('active','inactive') AND (effective_until IS NULL OR effective_until>effective_from)", name: "valid_budget_account_state"
    add_check_constraint :budget_accounts, "(purpose IN ('reserve','unassigned') AND organizational_unit_id IS NULL AND project_id IS NULL) OR (purpose='unit' AND organizational_unit_id IS NOT NULL AND project_id IS NULL) OR (purpose='project' AND project_id IS NOT NULL AND organizational_unit_id IS NULL)", name: "explicit_budget_owner"
    add_check_constraint :budget_periods, "currency='USD' AND status IN ('open','closed') AND EXTRACT(DAY FROM month_start)=1", name: "valid_utc_budget_month"
    add_check_constraint :priced_usage_receipts, "amount>=0 AND currency='USD' AND status IN ('posted','unresolved') AND ((status='posted')=(financial_transaction_id IS NOT NULL)) AND jsonb_typeof(payload->'amount')='string' AND (payload->>'amount')::numeric=amount", name: "valid_priced_receipt"
    add_check_constraint :financial_transactions, "currency='USD' AND amount>=0 AND (kind NOT IN ('funding','transfer') OR amount>0) AND kind IN ('funding','transfer','usage_charge','reversal','adjustment') AND EXTRACT(DAY FROM month_start)=1 AND length(reason) BETWEEN 1 AND 500 AND (original_transaction_id IS NULL OR original_transaction_id<>id)", name: "valid_financial_operation"
    execute <<~SQL
      CREATE FUNCTION business.financial_append_only() RETURNS trigger LANGUAGE plpgsql AS $$
      BEGIN RAISE EXCEPTION 'Financial history is append-only' USING ERRCODE='23514'; END $$;
      CREATE FUNCTION business.guard_financial_entry() RETURNS trigger LANGUAGE plpgsql AS $$
      BEGIN
        IF NOT EXISTS(SELECT 1 FROM business.financial_transactions t WHERE t.id=NEW.financial_transaction_id AND t.organization_id=NEW.organization_id AND t.write_transaction_id=txid_current())
        THEN RAISE EXCEPTION 'Entries must be created with their immutable transaction' USING ERRCODE='23514'; END IF;
        RETURN NEW;
      END $$;
      CREATE TRIGGER financial_entry_creation BEFORE INSERT ON business.ledger_entries FOR EACH ROW EXECUTE FUNCTION business.guard_financial_entry();
      CREATE FUNCTION business.check_financial_operation(p uuid) RETURNS void LANGUAGE plpgsql AS $$
      DECLARE t business.financial_transactions; original business.financial_transactions; n integer; f numeric; e numeric;
      BEGIN
        SELECT * INTO t FROM business.financial_transactions WHERE id=p;
        IF NOT FOUND THEN RETURN; END IF;
        PERFORM id FROM business.budget_periods WHERE id IN(SELECT budget_period_id FROM business.ledger_entries WHERE financial_transaction_id=p) ORDER BY id FOR UPDATE;
        SELECT COUNT(*),COALESCE(SUM(funding_delta),0),COALESCE(SUM(expense_delta),0) INTO n,f,e FROM business.ledger_entries WHERE financial_transaction_id=p;
        IF EXISTS(SELECT 1 FROM business.ledger_entries l JOIN business.budget_periods b ON b.id=l.budget_period_id JOIN business.budget_accounts a ON a.id=b.budget_account_id
          WHERE l.financial_transaction_id=p AND (b.month_start<>t.month_start OR b.currency<>t.currency OR a.currency<>t.currency))
        THEN RAISE EXCEPTION 'Ledger currency and accounting month must match' USING ERRCODE='23514'; END IF;
        IF t.kind<>'usage_charge' AND NOT EXISTS(SELECT 1 FROM business.users u JOIN business.role_assignments r ON r.user_id=u.id AND r.organization_id=u.organization_id WHERE u.id=t.actor_id AND u.organization_id=t.organization_id AND u.status='active' AND r.role='financial_operator' AND r.scope_type='organization')
        THEN RAISE EXCEPTION 'Explicit financial authority is required' USING ERRCODE='23514'; END IF;
        IF t.kind='funding' THEN
          IF n<>1 OR f<>t.amount OR e<>0 OR NOT EXISTS(SELECT 1 FROM business.ledger_entries l JOIN business.budget_periods b ON b.id=l.budget_period_id JOIN business.budget_accounts a ON a.id=b.budget_account_id WHERE l.financial_transaction_id=p AND a.purpose='reserve')
          THEN RAISE EXCEPTION 'Initial funding must enter one organizational reserve' USING ERRCODE='23514'; END IF;
        ELSIF t.kind='transfer' THEN
          IF n<>2 OR f<>0 OR e<>0 OR (SELECT COUNT(DISTINCT budget_period_id) FROM business.ledger_entries WHERE financial_transaction_id=p)<>2
            OR NOT EXISTS(SELECT 1 FROM business.ledger_entries WHERE financial_transaction_id=p AND funding_delta=t.amount AND expense_delta=0)
            OR NOT EXISTS(SELECT 1 FROM business.ledger_entries WHERE financial_transaction_id=p AND funding_delta=-t.amount AND expense_delta=0)
          THEN RAISE EXCEPTION 'Transfers require equal opposite funding entries' USING ERRCODE='23514'; END IF;
          IF EXISTS(SELECT 1 FROM business.ledger_entries debit WHERE debit.financial_transaction_id=p AND debit.funding_delta<0 AND
            (SELECT COALESCE(SUM(funding_delta-expense_delta),0) FROM business.ledger_entries WHERE budget_period_id=debit.budget_period_id)<0)
          THEN RAISE EXCEPTION 'A transfer cannot overdraw its funding source' USING ERRCODE='23514'; END IF;
        ELSE
          IF n<>1 OR f<>0 OR e<>(CASE WHEN t.kind='reversal' THEN -t.amount ELSE t.amount END)
          THEN RAISE EXCEPTION 'Expense operations require one exact expense entry' USING ERRCODE='23514'; END IF;
          IF t.kind='usage_charge' THEN
            IF NOT EXISTS(SELECT 1 FROM business.priced_usage_receipts r WHERE r.id=t.priced_usage_receipt_id AND r.organization_id=t.organization_id AND r.usage_event_id=t.usage_event_id AND r.amount=t.amount AND r.financial_transaction_id=t.id AND r.status='posted') OR t.source_type<>'priced_usage_event' OR t.source_id<>t.priced_usage_receipt_id::text
            THEN RAISE EXCEPTION 'Usage charges require their matching idempotent receipt' USING ERRCODE='23514'; END IF;
          ELSE
            SELECT * INTO original FROM business.financial_transactions WHERE id=t.original_transaction_id AND organization_id=t.organization_id;
            IF NOT FOUND OR original.kind NOT IN ('usage_charge','adjustment') OR original.currency<>t.currency OR original.month_start<>t.month_start
              OR (SELECT budget_period_id FROM business.ledger_entries WHERE financial_transaction_id=p)<>(SELECT budget_period_id FROM business.ledger_entries WHERE financial_transaction_id=original.id)
            THEN RAISE EXCEPTION 'Corrections must retain the original expense account and month' USING ERRCODE='23514'; END IF;
            IF t.kind='reversal' AND t.amount<>original.amount THEN RAISE EXCEPTION 'A reversal must exactly offset its origin' USING ERRCODE='23514'; END IF;
            IF t.kind='adjustment' AND (t.correction_group_id IS NULL OR NOT EXISTS(SELECT 1 FROM business.financial_transactions r WHERE r.kind='reversal' AND r.original_transaction_id=original.id AND r.correction_group_id=t.correction_group_id AND r.write_transaction_id=t.write_transaction_id))
            THEN RAISE EXCEPTION 'Replacement requires an atomic paired reversal' USING ERRCODE='23514'; END IF;
            IF t.kind='reversal' AND t.correction_group_id IS NOT NULL AND NOT EXISTS(SELECT 1 FROM business.financial_transactions a WHERE a.kind='adjustment' AND a.original_transaction_id=original.id AND a.correction_group_id=t.correction_group_id AND a.write_transaction_id=t.write_transaction_id)
            THEN RAISE EXCEPTION 'Correction reversal requires its paired replacement' USING ERRCODE='23514'; END IF;
          END IF;
        END IF;
      END $$;
      CREATE FUNCTION business.validate_financial_operation() RETURNS trigger LANGUAGE plpgsql AS $$
      BEGIN
        IF TG_TABLE_NAME='financial_transactions' THEN PERFORM business.check_financial_operation(NEW.id);
        ELSE PERFORM business.check_financial_operation(NEW.financial_transaction_id); END IF;
        RETURN NULL;
      END $$;
      CREATE CONSTRAINT TRIGGER financial_transaction_integrity AFTER INSERT ON business.financial_transactions DEFERRABLE INITIALLY DEFERRED FOR EACH ROW EXECUTE FUNCTION business.validate_financial_operation();
      CREATE CONSTRAINT TRIGGER ledger_entry_integrity AFTER INSERT ON business.ledger_entries DEFERRABLE INITIALLY DEFERRED FOR EACH ROW EXECUTE FUNCTION business.validate_financial_operation();
      CREATE FUNCTION business.protect_budget_identity() RETURNS trigger LANGUAGE plpgsql AS $$
      BEGIN
        IF TG_TABLE_NAME='budget_accounts' THEN
          IF NEW.organization_id<>OLD.organization_id OR NEW.purpose<>OLD.purpose OR NEW.organizational_unit_id IS DISTINCT FROM OLD.organizational_unit_id OR NEW.project_id IS DISTINCT FROM OLD.project_id OR NEW.currency<>OLD.currency OR NEW.effective_from<>OLD.effective_from
          THEN RAISE EXCEPTION 'Historical budget ownership is immutable' USING ERRCODE='23514'; END IF;
        ELSE
          IF NEW.organization_id<>OLD.organization_id OR NEW.budget_account_id<>OLD.budget_account_id OR NEW.month_start<>OLD.month_start OR NEW.currency<>OLD.currency
          THEN RAISE EXCEPTION 'Accounting period identity is immutable' USING ERRCODE='23514'; END IF;
        END IF;
        RETURN NEW;
      END $$;
      CREATE TRIGGER budget_account_identity BEFORE UPDATE ON business.budget_accounts FOR EACH ROW EXECUTE FUNCTION business.protect_budget_identity();
      CREATE TRIGGER budget_period_identity BEFORE UPDATE ON business.budget_periods FOR EACH ROW EXECUTE FUNCTION business.protect_budget_identity();
      CREATE FUNCTION business.protect_priced_receipt() RETURNS trigger LANGUAGE plpgsql AS $$
      BEGIN
        IF TG_OP='DELETE' OR NEW.id<>OLD.id OR NEW.organization_id<>OLD.organization_id OR NEW.usage_event_id<>OLD.usage_event_id OR NEW.user_id<>OLD.user_id OR NEW.project_id IS DISTINCT FROM OLD.project_id OR NEW.amount<>OLD.amount OR NEW.currency<>OLD.currency OR NEW.occurred_at<>OLD.occurred_at OR NEW.payload IS DISTINCT FROM OLD.payload OR NEW.payload_fingerprint<>OLD.payload_fingerprint OR NEW.created_at<>OLD.created_at OR (OLD.status='posted' AND (NEW.status<>'posted' OR NEW.financial_transaction_id IS DISTINCT FROM OLD.financial_transaction_id))
        THEN RAISE EXCEPTION 'Receipt source and posted effect are immutable' USING ERRCODE='23514'; END IF;
        RETURN NEW;
      END $$;
      CREATE TRIGGER receipt_source_immutable BEFORE UPDATE OR DELETE ON business.priced_usage_receipts FOR EACH ROW EXECUTE FUNCTION business.protect_priced_receipt();
    SQL
    %w[financial_transactions ledger_entries].each do |table|
      execute "CREATE TRIGGER #{table}_append_only BEFORE UPDATE OR DELETE ON business.#{table} FOR EACH ROW EXECUTE FUNCTION business.financial_append_only()"
      execute "CREATE TRIGGER #{table}_no_truncate BEFORE TRUNCATE ON business.#{table} FOR EACH STATEMENT EXECUTE FUNCTION business.financial_append_only()"
    end
  end

  def down
    raise ActiveRecord::IrreversibleMigration, "Append-only financial history must be retained"
  end

  private

  def tenant_fk(from, to, column)
    add_foreign_key from, to, column: [:organization_id, column], primary_key: [:organization_id, :id]
  end
end
