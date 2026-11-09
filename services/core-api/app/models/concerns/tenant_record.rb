module TenantRecord
  extend ActiveSupport::Concern

  included do
    belongs_to :organization
  end

  class_methods do
    def tenant_associations(*names)
      validate do
        names.each do |name|
          related = public_send(name)
          errors.add(name, "must belong to the same organization") if related && related.organization_id != organization_id
        end
      end
    end
  end
end
