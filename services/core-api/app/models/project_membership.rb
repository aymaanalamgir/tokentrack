class ProjectMembership < ApplicationRecord
  include TenantRecord
  belongs_to :user
  belongs_to :project
  tenant_associations :user, :project
  validates :user_id, uniqueness: { scope: :project_id }
  validates :project_role, inclusion: { in: %w[owner lead contributor reviewer] }
end
