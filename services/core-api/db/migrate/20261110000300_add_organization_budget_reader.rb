class AddOrganizationBudgetReader < ActiveRecord::Migration[8.1]
  def up
    remove_check_constraint :role_assignments,name:'valid_role_and_explicit_scope'
    add_check_constraint :role_assignments, <<~SQL.squish,name:'valid_role_and_explicit_scope'
      (role='employee' AND scope_type='self' AND organizational_unit_id IS NULL AND project_id IS NULL) OR
      (role IN ('organization_viewer','organization_budget_reader','project_creator','financial_operator') AND scope_type='organization' AND organizational_unit_id IS NULL AND project_id IS NULL) OR
      (role IN ('team_manager','team_budget_reader') AND scope_type='unit' AND organizational_unit_id IS NOT NULL AND project_id IS NULL) OR
      (role IN ('project_lead','project_budget_reader') AND scope_type='project' AND project_id IS NOT NULL AND organizational_unit_id IS NULL)
    SQL
  end
  def down
    raise ActiveRecord::IrreversibleMigration
  end
end
