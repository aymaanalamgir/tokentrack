class RequireRequestExecutionReference < ActiveRecord::Migration[8.1]
  def up
    execute <<~SQL
      ALTER TABLE business.financial_requests ADD CONSTRAINT approved_request_has_execution CHECK (
        (
          status='approved'
          AND (
            (request_type='personal_allowance' AND execution_revision_id IS NOT NULL AND execution_transaction_id IS NULL)
            OR
            (request_type IN ('project_funding','team_funding') AND execution_transaction_id IS NOT NULL AND execution_revision_id IS NULL)
          )
        )
        OR
        (status<>'approved' AND execution_revision_id IS NULL AND execution_transaction_id IS NULL)
      );
    SQL
  end

  def down
    raise ActiveRecord::IrreversibleMigration, "Preserve approved request execution integrity"
  end
end
