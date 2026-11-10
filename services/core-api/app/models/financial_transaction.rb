class FinancialTransaction < ApplicationRecord
  include TenantRecord
  belongs_to :actor, class_name: "User", optional: true
  belongs_to :user, optional: true
  belongs_to :project, optional: true
  belongs_to :home_unit, class_name: "OrganizationalUnit", optional: true
  belongs_to :priced_usage_receipt, optional: true
  belongs_to :original_transaction, class_name: "FinancialTransaction", optional: true
  has_many :ledger_entries
  tenant_associations :actor, :user, :project, :home_unit, :priced_usage_receipt, :original_transaction
  validates :kind, inclusion: { in: %w[funding transfer usage_charge reversal adjustment] }
  validate { errors.add(:amount, "must be nonnegative") if amount.nil? || amount.negative? }
  validates :reason, presence: true, length: { maximum: 500 }
  before_update { raise ActiveRecord::ReadOnlyRecord, "Financial history is append-only" }
  before_destroy { raise ActiveRecord::ReadOnlyRecord, "Financial history is append-only" }
end
