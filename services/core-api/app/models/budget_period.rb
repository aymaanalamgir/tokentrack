class BudgetPeriod < ApplicationRecord
  include TenantRecord
  belongs_to :budget_account
  has_many :ledger_entries
  tenant_associations :budget_account
  validates :month_start, uniqueness: { scope: :budget_account_id }
  validates :currency, inclusion: { in: ["USD"] }
  validates :status, inclusion: { in: %w[open closed] }
  def funding = ledger_entries.sum(:funding_delta)
  def expenditure = ledger_entries.sum(:expense_delta)
  def available = funding - expenditure
  def funded? = ledger_entries.where("funding_delta>0").exists?
end
