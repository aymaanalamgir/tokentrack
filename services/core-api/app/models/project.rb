class Project < ApplicationRecord
  include TenantRecord
  has_many :project_memberships
  has_many :users, through: :project_memberships
  validates :name, :slug, presence: true
  validates :name, length: { maximum: 120 }
  validates :description, length: { maximum: 5000 }
  validates :slug, uniqueness: { scope: :organization_id }, format: { with: /\A[a-z0-9]+(?:-[a-z0-9]+)*\z/ }
  validates :status, inclusion: { in: %w[active planned archived] }
end
