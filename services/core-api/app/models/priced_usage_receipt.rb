class PricedUsageReceipt < ApplicationRecord
  include TenantRecord
  belongs_to :user
  belongs_to :project, optional: true
  belongs_to :financial_transaction, optional: true
  tenant_associations :user, :project, :financial_transaction
  validates :usage_event_id, uniqueness: true
  validates :status, inclusion: { in: %w[posted unresolved] }
end
