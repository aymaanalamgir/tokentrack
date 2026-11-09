class ExtendProjectManagement < ActiveRecord::Migration[8.1]
  def up
    add_column :projects, :created_by_id, :uuid
    add_foreign_key :projects, :users, column: [:organization_id, :created_by_id], primary_key: [:organization_id, :id]
    add_column :projects, :archived_from_status, :string
    add_check_constraint :projects, "archived_from_status IS NULL OR archived_from_status IN ('planned', 'active')", name: "valid_project_restore_status"
    add_index :projects, [:organization_id, :created_by_id]

    add_column :project_memberships, :joined_at, :datetime
    add_column :project_memberships, :left_at, :datetime
    execute "UPDATE business.project_memberships SET joined_at = created_at"
    change_column_null :project_memberships, :joined_at, false
    change_column_default :project_memberships, :joined_at, -> { "CURRENT_TIMESTAMP" }
    remove_index :project_memberships, [:project_id, :user_id]
    add_index :project_memberships, [:project_id, :user_id], unique: true, where: "left_at IS NULL", name: "unique_active_project_membership"
    add_index :project_memberships, [:organization_id, :project_id, :left_at]
    add_check_constraint :project_memberships, "left_at IS NULL OR left_at >= joined_at", name: "valid_membership_period"

    remove_check_constraint :role_assignments, name: "valid_role_and_explicit_scope"
    add_check_constraint :role_assignments, <<~SQL.squish, name: "valid_role_and_explicit_scope"
      (role = 'employee' AND scope_type = 'self' AND organizational_unit_id IS NULL AND project_id IS NULL) OR
      (role IN ('organization_viewer', 'project_creator') AND scope_type = 'organization' AND organizational_unit_id IS NULL AND project_id IS NULL) OR
      (role = 'team_manager' AND scope_type = 'unit' AND organizational_unit_id IS NOT NULL AND project_id IS NULL) OR
      (role = 'project_lead' AND scope_type = 'project' AND project_id IS NOT NULL AND organizational_unit_id IS NULL)
    SQL

    # Preserve existing grants and IDs; repair a missing collaborator row before
    # enforcing that explicit project administrators are active participants.
    execute <<~SQL
      INSERT INTO business.project_memberships (id, organization_id, project_id, user_id, project_role, joined_at, created_at, updated_at)
        SELECT gen_random_uuid(), r.organization_id, r.project_id, r.user_id, 'owner', CURRENT_TIMESTAMP, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP
        FROM business.role_assignments r
        WHERE r.role = 'project_lead' AND NOT EXISTS (
          SELECT 1 FROM business.project_memberships m WHERE m.project_id = r.project_id AND m.user_id = r.user_id AND m.left_at IS NULL
        );

      CREATE FUNCTION business.check_project_administration(p uuid) RETURNS void LANGUAGE plpgsql AS $$
      BEGIN
        IF p IS NULL THEN RETURN; END IF;
        PERFORM id FROM business.projects WHERE id = p FOR UPDATE;
        IF NOT FOUND THEN RETURN; END IF;
        IF NOT EXISTS (
          SELECT 1 FROM business.role_assignments r
          JOIN business.users u ON u.id = r.user_id AND u.status = 'active'
          JOIN business.project_memberships m ON m.project_id = r.project_id AND m.user_id = r.user_id AND m.left_at IS NULL
          WHERE r.project_id = p AND r.role = 'project_lead'
        ) THEN RAISE EXCEPTION 'A project requires an active authorized administrator' USING ERRCODE = '23514'; END IF;
        IF EXISTS (
          SELECT 1 FROM business.role_assignments r JOIN business.users u ON u.id = r.user_id
          WHERE r.project_id = p AND r.role = 'project_lead' AND (
            u.status <> 'active' OR NOT EXISTS (
              SELECT 1 FROM business.project_memberships m WHERE m.project_id = p AND m.user_id = r.user_id AND m.left_at IS NULL
            )
          )
        ) THEN RAISE EXCEPTION 'Project authority requires active participation' USING ERRCODE = '23514'; END IF;
      END $$;

      CREATE FUNCTION business.validate_project_administration() RETURNS trigger LANGUAGE plpgsql AS $$
      BEGIN
        IF TG_TABLE_NAME = 'projects' THEN
          IF TG_OP <> 'DELETE' THEN PERFORM business.check_project_administration(NEW.id); END IF;
        ELSIF TG_TABLE_NAME = 'users' THEN
          PERFORM business.check_project_administration(r.project_id) FROM business.role_assignments r
            WHERE r.user_id = NEW.id AND r.role = 'project_lead';
        ELSE
          IF TG_OP <> 'INSERT' THEN PERFORM business.check_project_administration(OLD.project_id); END IF;
          IF TG_OP <> 'DELETE' THEN PERFORM business.check_project_administration(NEW.project_id); END IF;
        END IF;
        RETURN NULL;
      END $$;
    SQL
    %w[projects project_memberships role_assignments].each do |table|
      execute <<~SQL
        CREATE CONSTRAINT TRIGGER #{table}_administration_guard
          AFTER INSERT OR UPDATE OR DELETE ON business.#{table}
          DEFERRABLE INITIALLY DEFERRED FOR EACH ROW EXECUTE FUNCTION business.validate_project_administration();
      SQL
    end
    execute <<~SQL
      CREATE CONSTRAINT TRIGGER users_administration_guard AFTER UPDATE ON business.users
        DEFERRABLE INITIALLY DEFERRED FOR EACH ROW
        WHEN (OLD.status IS DISTINCT FROM NEW.status) EXECUTE FUNCTION business.validate_project_administration();
      SELECT business.check_project_administration(id) FROM business.projects;
    SQL
  end

  def down
    raise ActiveRecord::IrreversibleMigration, "Membership periods must be reconciled before restoring the old all-time uniqueness constraint"
  end
end
