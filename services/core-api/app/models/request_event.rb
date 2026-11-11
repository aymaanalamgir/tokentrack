class RequestEvent < ApplicationRecord
  include TenantRecord
  belongs_to :financial_request
  belongs_to :actor, class_name: "User"
  tenant_associations :financial_request, :actor
  validates :event_type, inclusion: { in: %w[created submitted escalated approved rejected cancelled executed] }
  validates :reason, presence: true, length: { maximum: 500 }
  validates :operation_key, presence: true, length: { maximum: 128 }, uniqueness: { scope: :financial_request_id }
  before_update { raise ActiveRecord::ReadOnlyRecord, "Request events are append-only" }
  before_destroy { raise ActiveRecord::ReadOnlyRecord, "Request events are append-only" }
end
