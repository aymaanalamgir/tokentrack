class SpendingLimit < ApplicationRecord
  include TenantRecord
  belongs_to :user
  belongs_to :current_revision,class_name:'SpendingLimitRevision',optional:true
  has_many :spending_limit_revisions
  tenant_associations :user,:current_revision
  validates :month_start,uniqueness:{scope:[:organization_id,:user_id,:currency]}
  validates :currency,inclusion:{in:['USD']}
end
