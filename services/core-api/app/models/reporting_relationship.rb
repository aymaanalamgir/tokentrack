class ReportingRelationship < ApplicationRecord
  include TenantRecord
  belongs_to :manager, class_name: "User"
  belongs_to :report, class_name: "User"
  tenant_associations :manager, :report
  validates :relationship_type, inclusion: { in: %w[line_manager dotted_line] }
  validates :report_id, uniqueness: { scope: :relationship_type }
  validate do
    if manager_id && report_id && (manager_id == report_id || Hierarchy.report_ids(organization_id, [report_id], excluding: id).include?(manager_id))
      errors.add(:manager, "would create a reporting cycle")
    end
  end
end
