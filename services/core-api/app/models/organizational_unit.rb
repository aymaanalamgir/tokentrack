class OrganizationalUnit < ApplicationRecord
  include TenantRecord
  belongs_to :parent_unit, class_name: "OrganizationalUnit", optional: true
  has_many :children, class_name: "OrganizationalUnit", foreign_key: :parent_unit_id
  has_many :organizational_memberships
  has_many :users, through: :organizational_memberships
  tenant_associations :parent_unit
  validates :name, :unit_type, presence: true
  validates :name, uniqueness: { scope: :organization_id }
  validate :acyclic_parent

  private

  def acyclic_parent
    return unless parent_unit_id && id
    descendants = Hierarchy.unit_ids(organization_id, [id])
    errors.add(:parent_unit, "would create a cycle") if parent_unit_id == id || descendants.include?(parent_unit_id)
  end
end
