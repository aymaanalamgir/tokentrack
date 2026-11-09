class Project < ApplicationRecord
  TRANSITIONS = { "planned" => %w[active archived], "active" => %w[planned archived], "archived" => %w[planned active] }.freeze
  include TenantRecord
  has_many :project_memberships
  has_many :active_project_memberships, -> { active }, class_name: "ProjectMembership"
  has_many :users, through: :active_project_memberships
  belongs_to :created_by, class_name: "User", optional: true
  tenant_associations :created_by
  validates :name, :slug, presence: true
  validates :name, length: { maximum: 120 }
  validates :description, length: { maximum: 5000 }
  validates :slug, uniqueness: { scope: :organization_id }, format: { with: /\A[a-z0-9]+(?:-[a-z0-9]+)*\z/ }
  validates :status, inclusion: { in: %w[active planned archived] }

  def archived? = status == "archived"
end
