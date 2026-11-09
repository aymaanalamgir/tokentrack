class Organization < ApplicationRecord
  validates :name, :slug, presence: true
  validates :slug, uniqueness: true, format: { with: /\A[a-z0-9]+(?:-[a-z0-9]+)*\z/ }
  has_many :users
  has_many :organizational_units
  has_many :projects
end
