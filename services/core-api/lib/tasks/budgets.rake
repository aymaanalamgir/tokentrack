namespace :budgets do
  desc 'Explicit local spending-control examples; no money created by allowances'
  task demo_setup: :environment do
    abort 'Local demo only' unless DemoSession.enabled?
    org=Organization.find_by!(slug:'aperture-technologies')
    finance=User.find_by!(organization:org,email:'olivia@aperture-technologies.example')
    jordan=User.find_by!(organization:org,email:'jordan@aperture-technologies.example')
    sofia=User.find_by!(organization:org,email:'sofia@aperture-technologies.example')
    marcus=User.find_by!(organization:org,email:'marcus@aperture-technologies.example')
    platform=OrganizationalUnit.find(DemoData.uuid('aperture-technologies/unit/platform'))
    months=BudgetPeriod.where(organization_id:org.id).distinct.order(:month_start).pluck(:month_start)
    abort 'Initialize finance periods first' if months.empty?
    service=Budgets::AllowanceOperations.new(finance)
    grant=service.delegate(manager_id:marcus.id,unit_id:platform.id,maximum_amount:'1000',from_month:months.first.strftime('%Y-%m'),until_month:months.last.strftime('%Y-%m'),request_key:'slice7-marcus-platform-v1',reason:'Explicit local demo delegation; direct reports only; monthly ceiling at most 1000 USD')
    months.each do |date|
      month=date.strftime('%Y-%m')
      [ [jordan,'500'],[sofia,'0.05'] ].each do |user,ceiling|
        next if SpendingLimit.exists?(organization:org,user:user,month_start:date)
        service.revise(user_id:user.id,month:month,amount:ceiling,expected_revision:nil,request_key:"slice7-ceiling-#{user.id}-#{month}",reason:user==sofia ? 'Explicit small control scenario using existing actual consumption; no artificial expense' : 'Explicit demo monthly spending ceiling, not funding',kind:'ceiling')
        next unless user==jordan
        root=SpendingLimit.find_by!(organization:org,user:user,month_start:date)
        projects=%w[fraud-detection developer-productivity].zip(%w[250 150]).map{|slug,amount|{project_id:Project.find_by!(organization:org,slug:slug).id,amount:amount}}
        Budgets::AllowanceOperations.new(user).revise(user_id:user.id,month:month,allocations:projects,expected_revision:root.current_revision_id,request_key:"slice7-allocation-#{month}",reason:'Personal partitioned controls: 400 allocated, 100 unallocated; not a funding movement',kind:'reallocation')
      end
    end
    small=nil
    if ENV['SMALL_BUDGET_SCENARIO']=='true'
      date=months.last
      account=BudgetAccount.find_by!(organization:org,purpose:'project',project_id:Project.find_by!(organization:org,slug:'fraud-detection').id)
      reserve=BudgetAccount.find_by!(organization:org,purpose:'reserve')
      period=account.budget_periods.find_by!(month_start:date)
      used=period.expenditure
      if used.positive?
        request_key="slice7-small-budget-#{date.strftime('%Y-%m')}"
        existing=FinancialTransaction.find_by(organization:org,source_type:'funding_transfer',source_id:request_key)
        amount=existing&.amount || (period.funding-used/BigDecimal('0.95')).round(15,BigDecimal::ROUND_DOWN)
        if amount.positive?
          tx=Finance::Operations.new(finance).transfer(from:account.id,to:reserve.id,month:date.strftime('%Y-%m'),amount:Finance::Money.string(amount),key:request_key,reason:'Explicit Slice 7 small project allocation demonstration: retain approximately 95% utilization, return unused funding to reserve; historical expenses unchanged')
          small={transaction_id:tx.id,amount:Finance::Money.string(tx.amount),month:date.strftime('%Y-%m')}
        end
      end
    end
    puts JSON.pretty_generate(delegation:grant.id,months:months.map{|m|m.strftime('%Y-%m')},personal_limits:SpendingLimit.where(organization:org).count,small_budget_transfer:small)
  end
end
