class AddAnalyticsIndexesAndReadGrants < ActiveRecord::Migration[8.1]
  def up
    remove_check_constraint :role_assignments,name:'valid_role_and_explicit_scope'
    add_check_constraint :role_assignments, <<~SQL.squish,name:'valid_role_and_explicit_scope'
      (role='employee' AND scope_type='self' AND organizational_unit_id IS NULL AND project_id IS NULL) OR
      (role IN ('organization_viewer','project_creator','financial_operator') AND scope_type='organization' AND organizational_unit_id IS NULL AND project_id IS NULL) OR
      (role IN ('team_manager','team_budget_reader') AND scope_type='unit' AND organizational_unit_id IS NOT NULL AND project_id IS NULL) OR
      (role IN ('project_lead','project_budget_reader') AND scope_type='project' AND project_id IS NOT NULL AND organizational_unit_id IS NULL)
    SQL
    add_index :priced_usage_receipts,[:organization_id,:occurred_at],name:'receipts_analytics_time'
    add_index :priced_usage_receipts,[:organization_id,:user_id,:occurred_at],name:'receipts_analytics_user'
    add_index :priced_usage_receipts,[:organization_id,:project_id,:occurred_at],name:'receipts_analytics_project'
    add_index :financial_transactions,:original_transaction_id,name:'financial_correction_parent'
    add_index :financial_transactions,[:organization_id,:created_at],name:'financial_posting_time'
  end
  def down
    raise ActiveRecord::IrreversibleMigration,'Preserve explicit read grants and additive reporting indexes'
  end
end
