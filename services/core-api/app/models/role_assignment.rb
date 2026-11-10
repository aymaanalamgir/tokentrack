class RoleAssignment < ApplicationRecord
  include TenantRecord
  SCOPES = { "employee" => "self", "organization_budget_reader" => "organization", "team_budget_reader" => "unit", "project_budget_reader" => "project", "organization_viewer" => "organization", "project_creator" => "organization", "financial_operator" => "organization", "team_manager" => "unit", "project_lead" => "project" }.freeze
  belongs_to :user
  belongs_to :organizational_unit, optional: true
  belongs_to :project, optional: true
  tenant_associations :user, :organizational_unit, :project
  validates :role, inclusion: { in: SCOPES.keys }
  validates :role, uniqueness: { scope: [:user_id, :scope_type, :organizational_unit_id, :project_id] }
  validate do
    errors.add(:scope_type, "does not match the role") unless SCOPES[role] == scope_type
    errors.add(:organizational_unit, "must match an explicit unit scope") unless (scope_type == "unit") == organizational_unit.present?
    errors.add(:project, "must match an explicit project scope") unless (scope_type == "project") == project.present?
  end
end
