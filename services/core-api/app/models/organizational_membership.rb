class OrganizationalMembership < ApplicationRecord
  include TenantRecord
  belongs_to :user
  belongs_to :organizational_unit
  tenant_associations :user, :organizational_unit
  validates :membership_type, presence: true
  validates :user_id, uniqueness: { scope: :organizational_unit_id }
  validates :user_id, uniqueness: { conditions: -> { where(is_primary: true) }, message: "already has a primary home team" }, if: :is_primary?
end
