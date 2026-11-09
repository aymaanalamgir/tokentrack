class CreateOrganizationalFoundation < ActiveRecord::Migration[8.1]
  def up
    create_table :organizations, id: :uuid do |t|
      t.string :name, null: false
      t.string :slug, null: false
      t.text :description
      t.boolean :demo, null: false, default: false
      t.timestamps
    end
    add_index :organizations, :slug, unique: true

    create_table :organizational_units, id: :uuid do |t|
      t.references :organization, type: :uuid, null: false, foreign_key: true
      t.uuid :parent_unit_id
      t.string :name, null: false
      t.string :unit_type, null: false
      t.text :description
      t.timestamps
    end
    create_table :users, id: :uuid do |t|
      t.references :organization, type: :uuid, null: false, foreign_key: true
      t.string :name, null: false
      t.string :email, null: false
      t.string :job_title, null: false
      t.string :job_function, null: false
      t.string :status, null: false, default: "active"
      t.boolean :demo_identity, null: false, default: false
      t.timestamps
    end
    create_table :projects, id: :uuid do |t|
      t.references :organization, type: :uuid, null: false, foreign_key: true
      t.string :name, null: false
      t.string :slug, null: false
      t.text :description
      t.string :status, null: false, default: "active"
      t.timestamps
    end
    %i[organizational_units users projects].each { |table| add_index table, [:organization_id, :id], unique: true }
    add_index :organizational_units, [:organization_id, :name], unique: true
    add_index :organizational_units, [:organization_id, :parent_unit_id]
    add_index :users, [:organization_id, :email], unique: true
    add_index :users, [:organization_id, :name]
    add_index :projects, [:organization_id, :slug], unique: true
    add_index :projects, [:organization_id, :status]
    tenant_fk :organizational_units, :organizational_units, :parent_unit_id
    add_check_constraint :organizational_units, "parent_unit_id IS NULL OR parent_unit_id <> id", name: "unit_not_own_parent"
    add_check_constraint :users, "status IN ('active', 'inactive')", name: "valid_user_status"
    add_check_constraint :projects, "status IN ('active', 'planned', 'archived')", name: "valid_project_status"

    create_table :organizational_memberships, id: :uuid do |t|
      t.references :organization, type: :uuid, null: false, foreign_key: true
      t.uuid :user_id, null: false
      t.uuid :organizational_unit_id, null: false
      t.boolean :is_primary, null: false, default: false
      t.string :membership_type, null: false, default: "member"
      t.timestamps
    end
    tenant_fk :organizational_memberships, :users, :user_id
    tenant_fk :organizational_memberships, :organizational_units, :organizational_unit_id
    add_index :organizational_memberships, [:user_id, :organizational_unit_id], unique: true, name: "unique_unit_membership"
    add_index :organizational_memberships, :user_id, unique: true, where: "is_primary", name: "one_primary_home_team"
    add_index :organizational_memberships, [:organization_id, :organizational_unit_id]

    create_table :reporting_relationships, id: :uuid do |t|
      t.references :organization, type: :uuid, null: false, foreign_key: true
      t.uuid :manager_id, null: false
      t.uuid :report_id, null: false
      t.string :relationship_type, null: false, default: "line_manager"
      t.timestamps
    end
    tenant_fk :reporting_relationships, :users, :manager_id
    tenant_fk :reporting_relationships, :users, :report_id
    add_check_constraint :reporting_relationships, "manager_id <> report_id", name: "no_self_reporting"
    add_check_constraint :reporting_relationships, "relationship_type IN ('line_manager', 'dotted_line')", name: "valid_reporting_type"
    add_index :reporting_relationships, [:report_id, :relationship_type], unique: true
    add_index :reporting_relationships, [:organization_id, :manager_id]

    create_table :project_memberships, id: :uuid do |t|
      t.references :organization, type: :uuid, null: false, foreign_key: true
      t.uuid :project_id, null: false
      t.uuid :user_id, null: false
      t.string :project_role, null: false, default: "contributor"
      t.timestamps
    end
    tenant_fk :project_memberships, :projects, :project_id
    tenant_fk :project_memberships, :users, :user_id
    add_index :project_memberships, [:project_id, :user_id], unique: true
    add_index :project_memberships, [:organization_id, :user_id]
    add_check_constraint :project_memberships, "project_role IN ('owner', 'lead', 'contributor', 'reviewer')", name: "valid_project_role"

    create_table :role_assignments, id: :uuid do |t|
      t.references :organization, type: :uuid, null: false, foreign_key: true
      t.uuid :user_id, null: false
      t.string :role, null: false
      t.string :scope_type, null: false
      t.uuid :organizational_unit_id
      t.uuid :project_id
      t.timestamps
    end
    tenant_fk :role_assignments, :users, :user_id
    tenant_fk :role_assignments, :organizational_units, :organizational_unit_id
    tenant_fk :role_assignments, :projects, :project_id
    add_index :role_assignments, [:organization_id, :user_id]
    execute <<~SQL
      CREATE UNIQUE INDEX unique_scoped_role ON business.role_assignments
        (user_id, role, scope_type, organizational_unit_id, project_id) NULLS NOT DISTINCT;
    SQL
    add_check_constraint :role_assignments, <<~SQL.squish, name: "valid_role_and_explicit_scope"
      (role = 'employee' AND scope_type = 'self' AND organizational_unit_id IS NULL AND project_id IS NULL) OR
      (role = 'organization_viewer' AND scope_type = 'organization' AND organizational_unit_id IS NULL AND project_id IS NULL) OR
      (role = 'team_manager' AND scope_type = 'unit' AND organizational_unit_id IS NOT NULL AND project_id IS NULL) OR
      (role = 'project_lead' AND scope_type = 'project' AND project_id IS NOT NULL AND organizational_unit_id IS NULL)
    SQL

    create_table :demo_sessions, id: :uuid do |t|
      t.references :organization, type: :uuid, null: false, foreign_key: true
      t.uuid :user_id, null: false
      t.string :token_digest, null: false
      t.datetime :expires_at, null: false
      t.timestamps
    end
    tenant_fk :demo_sessions, :users, :user_id
    add_index :demo_sessions, :token_digest, unique: true
    add_index :demo_sessions, :expires_at

    # Model validation gives useful errors; serialized database checks also protect
    # direct SQL writes and concurrent changes to an organization's hierarchy.
    execute <<~SQL
      CREATE FUNCTION business.check_unit_cycle() RETURNS trigger LANGUAGE plpgsql AS $$
      BEGIN
        PERFORM pg_advisory_xact_lock(hashtextextended(NEW.organization_id::text, 0));
        IF EXISTS (
          WITH RECURSIVE ancestors(id, parent_unit_id) AS (
            SELECT id, parent_unit_id FROM business.organizational_units
              WHERE id = NEW.parent_unit_id AND organization_id = NEW.organization_id
            UNION
            SELECT u.id, u.parent_unit_id FROM business.organizational_units u
              JOIN ancestors a ON u.id = a.parent_unit_id WHERE u.organization_id = NEW.organization_id
          ) SELECT 1 FROM ancestors WHERE id = NEW.id
        ) THEN RAISE EXCEPTION 'Organizational unit cycle' USING ERRCODE = '23514'; END IF;
        RETURN NEW;
      END $$;
      CREATE TRIGGER prevent_unit_cycle BEFORE INSERT OR UPDATE ON business.organizational_units
        FOR EACH ROW EXECUTE FUNCTION business.check_unit_cycle();

      CREATE FUNCTION business.check_reporting_cycle() RETURNS trigger LANGUAGE plpgsql AS $$
      BEGIN
        PERFORM pg_advisory_xact_lock(hashtextextended(NEW.organization_id::text, 0));
        IF EXISTS (
          WITH RECURSIVE ancestors(id) AS (
            SELECT NEW.manager_id
            UNION
            SELECT r.manager_id FROM business.reporting_relationships r JOIN ancestors a ON r.report_id = a.id
              WHERE r.organization_id = NEW.organization_id AND r.id <> NEW.id
          ) SELECT 1 FROM ancestors WHERE id = NEW.report_id
        ) THEN RAISE EXCEPTION 'Reporting relationship cycle' USING ERRCODE = '23514'; END IF;
        RETURN NEW;
      END $$;
      CREATE TRIGGER prevent_reporting_cycle BEFORE INSERT OR UPDATE ON business.reporting_relationships
        FOR EACH ROW EXECUTE FUNCTION business.check_reporting_cycle();
    SQL
  end

  def down
    %i[demo_sessions role_assignments project_memberships reporting_relationships organizational_memberships projects users organizational_units organizations].each { |table| drop_table table }
    execute "DROP FUNCTION business.check_unit_cycle(); DROP FUNCTION business.check_reporting_cycle();"
  end

  private

  def tenant_fk(from, to, column)
    add_foreign_key from, to, column: [:organization_id, column], primary_key: [:organization_id, :id]
  end
end
