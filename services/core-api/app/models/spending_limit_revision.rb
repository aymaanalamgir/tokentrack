class SpendingLimitRevision < ApplicationRecord
  include TenantRecord
  belongs_to :spending_limit
  belongs_to :set_by,class_name:'User'
  has_many :spending_limit_allocations
  tenant_associations :spending_limit,:set_by
  validates :reason,presence:true,length:{maximum:500}
  before_update { raise ActiveRecord::ReadOnlyRecord,'Allowance revisions are immutable' }
  before_destroy { raise ActiveRecord::ReadOnlyRecord,'Allowance revisions are immutable' }
end
