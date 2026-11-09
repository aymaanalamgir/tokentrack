class User < ApplicationRecord
  include TenantRecord
  has_many :organizational_memberships
  has_many :organizational_units, through: :organizational_memberships
  has_many :project_memberships, -> { active }
  has_many :project_membership_history, class_name: "ProjectMembership"
  has_many :projects, through: :project_memberships
  has_many :role_assignments
  has_many :manager_relationships, class_name: "ReportingRelationship", foreign_key: :report_id
  has_many :report_relationships, class_name: "ReportingRelationship", foreign_key: :manager_id
  validates :name, :email, :job_title, :job_function, presence: true
  validates :email, uniqueness: { scope: :organization_id }, format: { with: /\A[^\s@]+@[^\s@]+\.[^\s@]+\z/ }
  validates :status, inclusion: { in: %w[active inactive] }
  before_validation { self.email = email&.downcase }
end
