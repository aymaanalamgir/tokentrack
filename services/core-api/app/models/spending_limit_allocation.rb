class SpendingLimitAllocation < ApplicationRecord
  include TenantRecord
  belongs_to :spending_limit_revision
  belongs_to :project
  tenant_associations :spending_limit_revision,:project
  before_update { raise ActiveRecord::ReadOnlyRecord,'Allocation revisions are immutable' }
  before_destroy { raise ActiveRecord::ReadOnlyRecord,'Allocation revisions are immutable' }
end
