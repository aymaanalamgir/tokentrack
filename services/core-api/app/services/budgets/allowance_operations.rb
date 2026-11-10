module Budgets
  class AllowanceOperations
    def initialize(actor) = @actor=actor
    def revise(user_id:,month:,amount:nil,allocations:nil,expected_revision:nil,request_key:,reason:,kind:)
      date=Controls.month(month);Controls.key(request_key)
      raise Finance::Invalid,'A reason of 1–500 characters is required' unless reason.is_a?(String) && reason.length.between?(1,500)
      raise Finance::Invalid,'Invalid revision kind' unless %w[ceiling reallocation].include?(kind)
      ApplicationRecord.transaction do
        Finance::Money.lock("allowance_authority/#{@actor.organization_id}")
        actor=User.find(@actor.id);policy=AccessPolicy.new(actor)
        raise Finance::Forbidden unless actor.status=='active'
        user=User.where(organization_id:actor.organization_id).find(user_id)
        raise Finance::Invalid,'Inactive employee controls cannot be edited' unless user.status=='active'
        Finance::Money.lock("spending_limit/#{actor.organization_id}/#{user.id}/#{date}")
        root=SpendingLimit.lock.find_by(organization_id:actor.organization_id,user_id:user.id,month_start:date,currency:'USD')
        previous=root&.current_revision
        value=kind=='ceiling' ? Finance::Money.parse(amount) : previous&.limit_amount
        raise Finance::Invalid,'Establish a personal ceiling before allocating it' unless value
        allowed=kind=='ceiling' ? policy.manage_allowance?(user,value,date) : actor.id==user.id
        raise Finance::Forbidden,'Explicit allowance authority is required' unless allowed
        raise Finance::Invalid,'This allowance is closed' if root && root.status!='active'
        periods=BudgetPeriod.where(organization_id:actor.organization_id,month_start:date)
        raise Finance::Invalid,'This accounting month is closed' if periods.exists? && !periods.where(status:'open').exists?
        old=previous ? previous.spending_limit_allocations.pluck(:project_id,:limit_amount).to_h : {}
        chosen=allocations.nil? ? old : normalize_allocations(allocations)
        fingerprint=Finance::Money.fingerprint(user_id:user.id,month:date.to_s,amount:kind=='ceiling' ? Finance::Money.string(value) : nil,allocations:allocations.nil? ? nil : chosen.transform_values{|v|Finance::Money.string(v)}.sort.to_h,kind:kind,expected_revision:expected_revision,reason:reason,actor_id:actor.id)
        replay=root&.spending_limit_revisions&.find_by(request_key:request_key)
        if replay
          raise Finance::Conflict,'Operation key conflicts with its original request' unless replay.request_fingerprint==fingerprint
          next replay
        end
        raise Finance::Conflict,'Allowance changed. Reload before saving.' unless previous&.id==expected_revision
        raise Finance::Invalid,'Project sublimits exceed the personal ceiling' if chosen.values.sum>value
        projects=Project.where(organization_id:actor.organization_id,id:chosen.keys).index_by(&:id)
        raise ActiveRecord::RecordNotFound unless projects.size==chosen.size
        eligible=ProjectMembership.active.where(organization_id:actor.organization_id,user_id:user.id,project_id:chosen.keys).joins(:project).where.not(projects:{status:'archived'}).pluck(:project_id)
        chosen.each do |project_id,limit|
          raise Finance::Invalid,'New allocations require current project participation' if limit>old.fetch(project_id,0) && !eligible.include?(project_id)
        end
        if kind=='reallocation'
          consumed=Consumption.new(actor.organization_id,date).by_project(user.id)
          chosen.merge(old.reject{|id,_|chosen.key?(id)}.transform_values{0}).each do |id,new_limit|
            floor=[old.fetch(id,0),consumed.fetch(id,0)].min
            raise Finance::Invalid,'Only unused project capacity can be reallocated' if new_limit<floor
          end
          old_unallocated=previous.limit_amount-old.values.sum
          raise Finance::Invalid,'Unassigned usage already consumes this unallocated capacity' if value-chosen.values.sum<[old_unallocated,consumed.fetch(nil,0)].min
        end
        root ||= SpendingLimit.create!(organization_id:actor.organization_id,user:user,month_start:date,currency:'USD')
        revision=SpendingLimitRevision.create!(organization_id:actor.organization_id,spending_limit:root,revision_number:(previous&.revision_number||0)+1,limit_amount:value,set_by:actor,kind:kind,request_key:request_key,request_fingerprint:fingerprint,reason:reason)
        chosen.each{|id,limit|SpendingLimitAllocation.create!(organization_id:actor.organization_id,spending_limit_revision:revision,project_id:id,limit_amount:limit)}
        root.update!(current_revision:revision)
        revision
      end
    end
    def normalize_allocations(value)
      raise Finance::Invalid,'Provide at most 100 project sublimits' unless value.is_a?(Array) && value.size<=100
      rows=value.map do |row|
        raise Finance::Invalid,'Each sublimit needs project_id and amount' unless row.is_a?(Hash) && row.keys.map(&:to_s).sort==%w[amount project_id]
        row=row.stringify_keys
        raise Finance::Invalid,'Invalid project UUID' unless Analytics::Scope::UUID.match?(row['project_id'].to_s)
        [row['project_id'].downcase,Finance::Money.parse(row['amount'])]
      end
      raise Finance::Invalid,'A project cannot have duplicate sublimits' unless rows.map(&:first).uniq.size==rows.size
      rows.to_h
    end
    def delegate(manager_id:,unit_id:,maximum_amount:,from_month:,until_month:,request_key:,reason:)
      Controls.key(request_key);from=Controls.month(from_month);until_date=Controls.month(until_month);value=Finance::Money.parse(maximum_amount)
      raise Finance::Invalid,'Delegation must cover 1–12 months' unless from<=until_date && until_date<=from+11.months
      ApplicationRecord.transaction do
        Finance::Money.lock("allowance_authority/#{@actor.organization_id}")
        actor=User.find(@actor.id)
        raise Finance::Forbidden unless actor.status=='active' && AccessPolicy.new(actor).financial_operator?
        manager=User.where(organization_id:actor.organization_id,status:'active').find(manager_id)
        unit=OrganizationalUnit.where(organization_id:actor.organization_id).find(unit_id)
        raise Finance::Invalid,'Delegate must hold an explicit manager grant for this unit' unless RoleAssignment.exists?(organization_id:actor.organization_id,user_id:manager.id,role:'team_manager',organizational_unit_id:unit.id)
        payload={manager_id:manager.id,unit_id:unit.id,maximum_amount:Finance::Money.string(value),from_month:from.to_s,until_month:until_date.to_s,reason:reason,actor_id:actor.id}
        fingerprint=Finance::Money.fingerprint(payload)
        prior=AllowanceDelegation.find_by(organization_id:actor.organization_id,request_key:request_key)
        if prior
          raise Finance::Conflict,'Delegation key conflicts' unless prior.request_fingerprint==fingerprint
          next prior
        end
        AllowanceDelegation.create!(organization_id:actor.organization_id,manager:manager,organizational_unit:unit,granted_by:actor,maximum_amount:value,effective_from_month:from,effective_until_month:until_date,request_key:request_key,request_fingerprint:fingerprint,reason:reason)
      end
    end
    def revoke(id)
      ApplicationRecord.transaction do
        Finance::Money.lock("allowance_authority/#{@actor.organization_id}")
        actor=User.find(@actor.id)
        raise Finance::Forbidden unless actor.status=='active' && AccessPolicy.new(actor).financial_operator?
        grant=AllowanceDelegation.where(organization_id:actor.organization_id).lock.find(id)
        grant.update!(revoked_at:Time.current,revoked_by:actor) unless grant.revoked_at
        grant
      end
    end
  end
end
