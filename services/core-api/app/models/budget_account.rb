class BudgetAccount < ApplicationRecord
  include TenantRecord
  belongs_to :organizational_unit, optional: true
  belongs_to :project, optional: true
  has_many :budget_periods
  tenant_associations :organizational_unit, :project
  validates :name, presence: true, length: { maximum: 120 }
  validates :purpose, inclusion: { in: %w[reserve unassigned unit project] }
  validates :currency, inclusion: { in: ["USD"] }
  validates :status, inclusion: { in: %w[active inactive] }
end
