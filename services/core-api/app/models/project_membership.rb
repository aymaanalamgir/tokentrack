class ProjectMembership < ApplicationRecord
  include TenantRecord
  belongs_to :user
  belongs_to :project
  tenant_associations :user, :project
  scope :active, -> { where(left_at: nil) }
  scope :past, -> { where.not(left_at: nil) }
  before_validation { self.joined_at ||= Time.current }
  validates :joined_at, presence: true
  validates :user_id, uniqueness: { scope: :project_id, conditions: -> { active } }, if: -> { left_at.nil? }
  validates :project_role, inclusion: { in: %w[owner lead contributor reviewer] }
  validate { errors.add(:left_at, "cannot precede joining") if left_at && joined_at && left_at < joined_at }
end
