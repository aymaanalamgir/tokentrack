class CreateSpendingControls < ActiveRecord::Migration[8.1]
  def up
    create_table :spending_limits,id: :uuid do |t|
      t.uuid :organization_id,null:false
      t.uuid :user_id,null:false
      t.date :month_start,null:false
      t.string :currency,null:false,default:'USD'
      t.string :status,null:false,default:'active'
      t.uuid :current_revision_id
      t.timestamps
    end
    create_table :spending_limit_revisions,id: :uuid do |t|
      t.uuid :organization_id,null:false
      t.uuid :spending_limit_id,null:false
      t.integer :revision_number,null:false
      t.decimal :limit_amount,precision:38,scale:15,null:false
      t.uuid :set_by_id,null:false
      t.string :kind,null:false
      t.string :request_key,null:false,limit:128
      t.string :request_fingerprint,null:false,limit:64
      t.string :reason,null:false,limit:500
      t.bigint :write_transaction_id,null:false,default: -> {'txid_current()'}
      t.datetime :created_at,null:false,default: -> {'CURRENT_TIMESTAMP'}
    end
    create_table :spending_limit_allocations,id: :uuid do |t|
      t.uuid :organization_id,null:false
      t.uuid :spending_limit_revision_id,null:false
      t.uuid :project_id,null:false
      t.decimal :limit_amount,precision:38,scale:15,null:false
      t.datetime :created_at,null:false,default: -> {'CURRENT_TIMESTAMP'}
    end
    create_table :allowance_delegations,id: :uuid do |t|
      t.uuid :organization_id,null:false
      t.uuid :manager_id,null:false
      t.uuid :organizational_unit_id,null:false
      t.uuid :granted_by_id,null:false
      t.decimal :maximum_amount,precision:38,scale:15,null:false
      t.date :effective_from_month,null:false
      t.date :effective_until_month,null:false
      t.string :request_key,null:false,limit:128
      t.string :request_fingerprint,null:false,limit:64
      t.string :reason,null:false,limit:500
      t.datetime :revoked_at
      t.uuid :revoked_by_id
      t.datetime :created_at,null:false,default: -> {'CURRENT_TIMESTAMP'}
    end
    %i[spending_limits spending_limit_revisions spending_limit_allocations allowance_delegations].each do |table|
      add_index table,[:organization_id,:id],unique:true
      add_foreign_key table,:organizations
    end
    add_index :spending_limits,[:organization_id,:user_id,:month_start,:currency],unique:true,name:'one_monthly_personal_ceiling'
    add_index :spending_limit_revisions,[:spending_limit_id,:revision_number],unique:true,name:'unique_allowance_revision_number'
    add_index :spending_limit_revisions,[:spending_limit_id,:request_key],unique:true,name:'idempotent_allowance_revision'
    add_index :spending_limit_allocations,[:spending_limit_revision_id,:project_id],unique:true,name:'one_project_per_allowance_revision'
    add_index :allowance_delegations,[:organization_id,:request_key],unique:true,name:'idempotent_allowance_delegation'
    add_index :allowance_delegations,[:organization_id,:manager_id,:revoked_at],name:'active_allowance_delegations'
    fk :spending_limits,:users,:user_id
    fk :spending_limit_revisions,:spending_limits,:spending_limit_id
    fk :spending_limit_revisions,:users,:set_by_id
    fk :spending_limit_allocations,:spending_limit_revisions,:spending_limit_revision_id
    fk :spending_limit_allocations,:projects,:project_id
    fk :allowance_delegations,:users,:manager_id
    fk :allowance_delegations,:users,:granted_by_id
    fk :allowance_delegations,:users,:revoked_by_id
    fk :allowance_delegations,:organizational_units,:organizational_unit_id
    execute <<~SQL
      ALTER TABLE business.spending_limits ADD CONSTRAINT current_revision_same_tenant FOREIGN KEY(organization_id,current_revision_id) REFERENCES business.spending_limit_revisions(organization_id,id) DEFERRABLE INITIALLY DEFERRED;
      ALTER TABLE business.spending_limits ADD CHECK(currency='USD' AND status IN ('active','closed') AND EXTRACT(DAY FROM month_start)=1 AND month_start BETWEEN '2000-01-01' AND '2099-12-01');
      ALTER TABLE business.spending_limit_revisions ADD CHECK(limit_amount>=0 AND limit_amount<'Infinity'::numeric AND revision_number>0 AND kind IN ('ceiling','reallocation') AND length(reason)>0);
      ALTER TABLE business.spending_limit_allocations ADD CHECK(limit_amount>=0 AND limit_amount<'Infinity'::numeric);
      ALTER TABLE business.allowance_delegations ADD CHECK(maximum_amount>=0 AND maximum_amount<'Infinity'::numeric AND EXTRACT(DAY FROM effective_from_month)=1 AND EXTRACT(DAY FROM effective_until_month)=1 AND effective_from_month<=effective_until_month AND (revoked_at IS NULL)=(revoked_by_id IS NULL));
      CREATE FUNCTION business.guard_spending_control() RETURNS trigger LANGUAGE plpgsql AS $$
      BEGIN
        IF TG_OP IN ('DELETE','TRUNCATE') THEN RAISE EXCEPTION 'Spending control history is append-only' USING ERRCODE='23514'; END IF;
        IF TG_TABLE_NAME='spending_limits' THEN
          IF NEW.organization_id<>OLD.organization_id OR NEW.user_id<>OLD.user_id OR NEW.month_start<>OLD.month_start OR NEW.currency<>OLD.currency OR NEW.created_at<>OLD.created_at
          THEN RAISE EXCEPTION 'Spending limit identity is immutable' USING ERRCODE='23514'; END IF;
          RETURN NEW;
        ELSIF TG_TABLE_NAME='allowance_delegations' AND OLD.revoked_at IS NULL AND NEW.revoked_at IS NOT NULL AND NEW.revoked_by_id IS NOT NULL AND (to_jsonb(NEW)-'revoked_at'-'revoked_by_id')=(to_jsonb(OLD)-'revoked_at'-'revoked_by_id') THEN
          RETURN NEW;
        END IF;
        RAISE EXCEPTION 'Spending control history is append-only' USING ERRCODE='23514';
      END $$;
      CREATE TRIGGER spending_limits_identity BEFORE UPDATE OR DELETE ON business.spending_limits FOR EACH ROW EXECUTE FUNCTION business.guard_spending_control();
      CREATE TRIGGER spending_limits_no_truncate BEFORE TRUNCATE ON business.spending_limits FOR EACH STATEMENT EXECUTE FUNCTION business.guard_spending_control();
      CREATE FUNCTION business.validate_spending_revision() RETURNS trigger LANGUAGE plpgsql AS $$
      DECLARE root_id uuid; current_id uuid; ceiling numeric; allocated numeric; root_org uuid; maximum_revision integer;
      BEGIN
        IF TG_TABLE_NAME='spending_limits' THEN root_id=NEW.id;
        ELSIF TG_TABLE_NAME='spending_limit_allocations' THEN SELECT spending_limit_id INTO root_id FROM business.spending_limit_revisions WHERE id=NEW.spending_limit_revision_id;
        ELSE root_id=NEW.spending_limit_id; END IF;
        SELECT current_revision_id,organization_id INTO current_id,root_org FROM business.spending_limits WHERE id=root_id;
        IF current_id IS NULL OR NOT EXISTS(SELECT 1 FROM business.spending_limit_revisions WHERE id=current_id AND spending_limit_id=root_id AND organization_id=root_org) THEN
          RAISE EXCEPTION 'A spending limit needs its own current revision' USING ERRCODE='23514'; END IF;
        SELECT MAX(revision_number) INTO maximum_revision FROM business.spending_limit_revisions WHERE spending_limit_id=root_id;
        IF NOT EXISTS(SELECT 1 FROM business.spending_limit_revisions WHERE id=current_id AND revision_number=maximum_revision) THEN RAISE EXCEPTION 'Current revision must be latest' USING ERRCODE='23514'; END IF;
        IF EXISTS(SELECT 1 FROM business.spending_limit_revisions r LEFT JOIN business.spending_limit_allocations a ON a.spending_limit_revision_id=r.id WHERE r.spending_limit_id=root_id GROUP BY r.id HAVING COALESCE(SUM(a.limit_amount),0)>r.limit_amount) THEN
          RAISE EXCEPTION 'Project sublimits exceed personal ceiling' USING ERRCODE='23514'; END IF;
        RETURN NULL;
      END $$;
      CREATE FUNCTION business.guard_spending_allocation_insert() RETURNS trigger LANGUAGE plpgsql AS $$
      BEGIN
        IF NOT EXISTS(SELECT 1 FROM business.spending_limit_revisions WHERE id=NEW.spending_limit_revision_id AND write_transaction_id=txid_current()) THEN RAISE EXCEPTION 'Allocations must be inserted with their revision' USING ERRCODE='23514'; END IF;
        RETURN NEW;
      END $$;
      CREATE TRIGGER allocation_same_transaction BEFORE INSERT ON business.spending_limit_allocations FOR EACH ROW EXECUTE FUNCTION business.guard_spending_allocation_insert();
    SQL
    %w[spending_limits spending_limit_revisions spending_limit_allocations].each do |table|
      execute "CREATE CONSTRAINT TRIGGER #{table}_valid_revision AFTER INSERT OR UPDATE ON business.#{table} DEFERRABLE INITIALLY DEFERRED FOR EACH ROW EXECUTE FUNCTION business.validate_spending_revision()"
    end
    %w[spending_limit_revisions spending_limit_allocations allowance_delegations].each do |table|
      execute "CREATE TRIGGER #{table}_immutable BEFORE UPDATE OR DELETE ON business.#{table} FOR EACH ROW EXECUTE FUNCTION business.guard_spending_control()"
      execute "CREATE TRIGGER #{table}_no_truncate BEFORE TRUNCATE ON business.#{table} FOR EACH STATEMENT EXECUTE FUNCTION business.guard_spending_control()"
    end
  end
  def down
    raise ActiveRecord::IrreversibleMigration,'Preserve spending control revision history'
  end
  private
  def fk(from,to,column)
    execute "ALTER TABLE business.#{from} ADD FOREIGN KEY(organization_id,#{column}) REFERENCES business.#{to}(organization_id,id)"
  end
end
