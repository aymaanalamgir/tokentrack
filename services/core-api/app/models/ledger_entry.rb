class LedgerEntry < ApplicationRecord
  include TenantRecord
  belongs_to :financial_transaction
  belongs_to :budget_period
  tenant_associations :financial_transaction, :budget_period
  before_update { raise ActiveRecord::ReadOnlyRecord, "Ledger entries are append-only" }
  before_destroy { raise ActiveRecord::ReadOnlyRecord, "Ledger entries are append-only" }
end
