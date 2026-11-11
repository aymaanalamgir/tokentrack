class FinancialRequest < ApplicationRecord
  include TenantRecord
  TYPES = %w[personal_allowance project_funding team_funding].freeze
  STATUSES = %w[pending approved rejected cancelled].freeze

  belongs_to :requester, class_name: "User"
  belongs_to :target_user, class_name: "User", optional: true
  belongs_to :target_project, class_name: "Project", optional: true
  belongs_to :target_unit, class_name: "OrganizationalUnit", optional: true
  belongs_to :target_budget_account, class_name: "BudgetAccount", optional: true
  belongs_to :source_budget_account, class_name: "BudgetAccount", optional: true
  belongs_to :assigned_approver, class_name: "User", optional: true
  belongs_to :allowance_revision_snapshot, class_name: "SpendingLimitRevision", optional: true
  belongs_to :execution_transaction, class_name: "FinancialTransaction", optional: true
  belongs_to :execution_revision, class_name: "SpendingLimitRevision", optional: true
  has_many :request_events
  tenant_associations :requester, :target_user, :target_project, :target_unit,
    :target_budget_account, :source_budget_account, :assigned_approver,
    :allowance_revision_snapshot, :execution_transaction, :execution_revision

  validates :request_type, inclusion: { in: TYPES }
  validates :status, inclusion: { in: STATUSES }
  validates :currency, inclusion: { in: ["USD"] }
  validates :reason, :routing_reason, presence: true, length: { maximum: 500 }
  validates :request_key, presence: true, length: { maximum: 128 }
  validates :request_key, uniqueness: { scope: [:organization_id, :requester_id] }
  validates :requested_amount, numericality: { greater_than: 0 }
  validates :current_amount_snapshot, numericality: { greater_than_or_equal_to: 0 }
  before_destroy { raise ActiveRecord::ReadOnlyRecord, "Request history is append-only" }

  def pending? = status == "pending"
  def funding? = %w[project_funding team_funding].include?(request_type)
end
