class AllowanceDelegation < ApplicationRecord
  include TenantRecord
  belongs_to :manager,class_name:'User'
  belongs_to :granted_by,class_name:'User'
  belongs_to :revoked_by,class_name:'User',optional:true
  belongs_to :organizational_unit
  tenant_associations :manager,:granted_by,:revoked_by,:organizational_unit
  validates :reason,presence:true,length:{maximum:500}
  scope :active, -> {where(revoked_at:nil)}
  before_destroy { raise ActiveRecord::ReadOnlyRecord,'Delegation history is immutable' }
end
