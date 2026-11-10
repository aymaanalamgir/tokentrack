module Budgets
  class Report
    def initialize(actor,params={})
      @actor=actor;@policy=AccessPolicy.new(actor);@params=params.stringify_keys;@organization=actor.organization_id
      raise Finance::Invalid,'Unknown budget filter' unless (@params.keys-%w[month user_id project_id organization_unit_id account_id as_of limit offset history_offset]).empty?
      @month=@params['month'] ? Controls.month(@params['month']) : (SpendingLimit.where(organization_id:@organization,user_id:actor.id).maximum(:month_start)||BudgetPeriod.where(organization_id:@organization).minimum(:month_start)||Time.now.utc.to_date.beginning_of_month)
      %w[user_id project_id organization_unit_id account_id].each{|key|raise Finance::Invalid,'Invalid budget identifier' if @params[key] && !Analytics::Scope::UUID.match?(@params[key])}
      @limit=integer('limit',25,1..100);@offset=integer('offset',0,0..100000);@history_offset=integer('history_offset',0,0..100000)
      @as_of=@params['as_of'] && Date.iso8601(@params['as_of'])
      raise Finance::Invalid,'As-of date must be within the selected month' if @as_of && @as_of.beginning_of_month!=@month
    rescue Date::Error
      raise Finance::Invalid,'Use an ISO as-of date'
    end
    def call
      return perform if ApplicationRecord.connection.transaction_open?
      ApplicationRecord.transaction(isolation: :repeatable_read,requires_new:true) { perform }
    end
    def perform
      if @params['project_id']
        project=Project.where(organization_id:@organization).find(@params['project_id'])
        raise ActiveRecord::RecordNotFound unless @policy.project?(project) || @policy.budget_org_reader? || @policy.budget_project_ids.include?(project.id)
      end
      allowed=@policy.allowance_read_user_ids
      selected=User.where(organization_id:@organization).includes(:organizational_memberships).find(@params['user_id']||@actor.id)
      raise ActiveRecord::RecordNotFound unless allowed.include?(selected.id)
      people_scope=User.where(organization_id:@organization,id:allowed).order(:name)
      people=people_scope.includes(:organizational_memberships).limit(@limit).offset(@offset).to_a
      ids=(people.map(&:id)+[selected.id]).uniq
      consumption=Consumption.new(@organization,@month)
      amounts=consumption.batch(ids)
      roots=SpendingLimit.where(organization_id:@organization,user_id:ids,month_start:@month).includes(current_revision:{spending_limit_allocations: :project}).index_by(&:user_id)
      @as_of ||= PricedUsageReceipt.where(organization_id:@organization,occurred_at:Controls.utc(@month)...Controls.utc(@month.next_month)).maximum(:occurred_at)&.utc&.to_date
      @coverage=coverage(ids)
      periods=BudgetPeriod.where(organization_id:@organization,month_start:@month)
      @controls_open=!periods.exists? || periods.where(status:'open').exists?
      own=allowance(selected,roots[selected.id],amounts.fetch(selected.id,{}))
      personal_rows=people.map{|person|allowance(person,roots[person.id],amounts.fetch(person.id,{}),details:false)}
      accounts=account_rows
      funding=accounts.sum{|r|BigDecimal(r['funding'])};expenditure=accounts.sum{|r|BigDecimal(r['expenditure'])}
      own_ids=[selected.id]
      {month:@month.strftime('%Y-%m'),currency:'USD',as_of:@as_of&.to_s,own_allowance:own,employees:personal_rows,employees_meta:{total:people_scope.count,limit:@limit,offset:@offset},accounts:accounts,
       summary:accounts.empty? ? nil : Controls.warning(expenditure,funding,zero_state:'no_funding').merge(funding:Finance::Money.string(funding),net_expenditure:Finance::Money.string(expenditure),basis:'Authorized funded accounts only; not employee-attributed costs'),
       coverage:@coverage,trend:accounts.empty? ? consumption.daily(own_ids) : account_trend(accounts.map{|a|a['period_id']}),
       projects:eligible_projects(selected).map{|p|{id:p.id,name:p.name}},history:transfer_history(accounts),
       delegations:delegations,delegation_options:delegation_options,project_contributors:project_contributors,
       capabilities:{transfer:@policy.financial_operator?,fund:@policy.financial_operator?,initialize_month:@policy.financial_operator?,delegate:@policy.financial_operator?,allocate_self:selected.id==@actor.id && roots[selected.id]&.status!='closed'},
       available_months:BudgetPeriod.where(organization_id:@organization).distinct.order(:month_start).pluck(:month_start).map{|m|m.strftime('%Y-%m')},
       thresholds:Rails.application.config.x.budget_thresholds||{approaching:75,high:90,reached:100}}
    end
    def allowance(user,root,amounts,details:true)
      revision=root&.current_revision;limit=revision&.limit_amount;used=amounts.values.sum
      allocations=revision ? revision.spending_limit_allocations.to_h{|a|[a.project_id,a.limit_amount]} : {}
      cap=@policy.allowance_maximum(user,@month)
      row={user_id:user.id,name:user.name,job_function:user.job_function,id:root&.id,revision_id:revision&.id,revision_number:revision&.revision_number,status:root&.status||'not_established',consumption:Finance::Money.string(used),ceiling:limit && Finance::Money.string(limit),allocated:Finance::Money.string(allocations.values.sum),can_manage:!cap.nil? && @controls_open && root&.status!='closed',delegated_maximum:cap==:unlimited ? nil : cap && Finance::Money.string(cap),can_allocate:user.id==@actor.id && root&.status=='active' && @controls_open}
      row.merge!(limit ? Controls.warning(used,limit) : {remaining:nil,utilization_percent:nil,warning:'not_established'})
      return row unless details
      names=Project.where(organization_id:@organization,id:(allocations.keys+amounts.keys.compact)).pluck(:id,:name).to_h
      eligible=eligible_projects(user).map(&:id)
      projects=(allocations.keys+amounts.keys.compact).uniq.map do |id|
        {project_id:id,name:names[id],eligible:eligible.include?(id)}.merge(Controls.warning(amounts.fetch(id,0),allocations.fetch(id,0)))
      end
      projects=[] unless limit
      unallocated=limit ? limit-allocations.values.sum : nil
      asof=Consumption.new(@organization,@month,as_of:@as_of)
      asof_used=asof.by_project(user.id).values.sum
      row.merge(projects:projects,unallocated:unallocated && Controls.warning(amounts.fetch(nil,0),unallocated),forecast:Controls.forecast(asof_used,month:@month,as_of:@as_of,coverage_incomplete:incomplete?,observed_days:asof.observed_days([user.id])),revisions:root ? root.spending_limit_revisions.order(revision_number: :desc).limit(20).includes(:set_by).map{|r|{id:r.id,number:r.revision_number,kind:r.kind,ceiling:Finance::Money.string(r.limit_amount),actor:r.set_by.name,reason:r.reason,created_at:r.created_at}} : [])
    end
    def eligible_projects(user)
      Project.where(organization_id:@organization,id:ProjectMembership.active.where(organization_id:@organization,user_id:user.id).select(:project_id)).where.not(status:'archived').order(:name).to_a
    end
    def account_rows
      periods=BudgetPeriod.where(organization_id:@organization,month_start:@month).joins(:budget_account)
      unless @policy.budget_org_reader?
        periods=periods.where('budget_accounts.organizational_unit_id IN (?) OR budget_accounts.project_id IN (?)',@policy.budget_unit_ids,@policy.budget_project_ids)
      end
      if @params['organization_unit_id']
        raise ActiveRecord::RecordNotFound unless @policy.budget_org_reader? || @policy.budget_unit_ids.include?(@params['organization_unit_id'])
        periods=periods.where('budget_accounts.organizational_unit_id=?',@params['organization_unit_id'])
      end
      periods=periods.where(budget_account_id:@params['account_id']) if @params['account_id']
      periods=periods.where('budget_accounts.project_id=?',@params['project_id']) if @params['project_id']
      rows=ApplicationRecord.connection.select_all("SELECT a.id::text AS id,p.id::text AS period_id,a.project_id::text AS project_id,a.organizational_unit_id::text AS organizational_unit_id,a.name,a.purpose,p.status,a.status AS account_status,SUM(e.funding_delta) AS funding,SUM(e.expense_delta) AS expenditure FROM business.budget_accounts a JOIN business.budget_periods p ON p.budget_account_id=a.id LEFT JOIN business.ledger_entries e ON e.budget_period_id=p.id WHERE p.id IN (#{periods.select('budget_periods.id').to_sql}) GROUP BY a.id,p.id ORDER BY a.name").to_a
      raise ActiveRecord::RecordNotFound if @params['account_id'] && rows.empty?
      c=ApplicationRecord.connection;ids=rows.map{|r|r['period_id']}
      forecasts={}
      unless ids.empty?
        query=Consumption.new(@organization,@month,as_of:@as_of).query
        days=query.rows(query.cte+"SELECT budget_period_id::text AS period_id,occurred_at::date::text AS day,SUM(expense_delta) AS used FROM expenses WHERE budget_period_id IN (#{ids.map{|id|c.quote(id)}.join(',')}) GROUP BY budget_period_id,day")
        forecasts=days.group_by{|r|r['period_id']}
      end
      rows.map do |r|
        funding=BigDecimal((r['funding']||0).to_s);used=BigDecimal((r['expenditure']||0).to_s)
        days=forecasts.fetch(r['period_id'],[])
        forecast=Controls.forecast(days.sum{|d|BigDecimal(d['used'].to_s)},month:@month,as_of:@as_of,coverage_incomplete:true,observed_days:days.size)
        r.merge('funding'=>Finance::Money.string(funding),'expenditure'=>Finance::Money.string(used),'control'=>Controls.warning(used,funding,zero_state:'no_funding'),'forecast'=>forecast.merge(projected_overage:forecast[:projected] && Finance::Money.string([BigDecimal(forecast[:projected])-funding,0].max)))
      end
    end
    def account_trend(ids,asof:nil)
      return [] if ids.empty?
      c=ApplicationRecord.connection;query=Consumption.new(@organization,@month,as_of:asof).query
      query.rows(query.cte+"SELECT occurred_at::date::text AS day,SUM(expense_delta) AS net_expenditure,COUNT(DISTINCT occurred_at::date) AS observed_days FROM expenses WHERE budget_period_id IN (#{ids.map{|id|c.quote(id)}.join(',')}) GROUP BY day ORDER BY day").map{|r|r.merge('net_expenditure'=>Finance::Money.string(r['net_expenditure']))}
    end
    def account_forecast(id)
      days=account_trend([id],asof:@as_of)
      Controls.forecast(days.sum{|r|BigDecimal(r['net_expenditure'])},month:@month,as_of:@as_of,coverage_incomplete:incomplete?,observed_days:days.size)
    end
    def coverage(ids)
      dates={start:Controls.utc(@month).iso8601,end:Controls.utc(@month.next_month).iso8601}
      result=Analytics::UsageClient.new.call({organization_id:@organization,all_users:false,scope_users:ids,scope_projects:[],filter_users:nil,granularity:'day',project_id:nil,user_id:nil,provider:nil,model:nil,tool:nil}.merge(dates))
      {status:'available',basis:'Personal/managed allowance activity; separate from funded-account ownership',metrics:result['totals'],available_range:result['available_range']}
    rescue Analytics::Unavailable
      {status:'unavailable',basis:'Pricing coverage could not be confirmed; posted ledger costs remain available'}
    end
    def incomplete? = @coverage[:status]!='available' || @coverage.dig(:metrics,'unpriced_events').to_i>0 || @coverage.dig(:metrics,'pending_delivery').to_i>0
    def transfer_history(accounts)
      ids=accounts.map{|a|a['period_id']}
      scope=FinancialTransaction.where(organization_id:@organization,month_start:@month,kind:%w[funding transfer]).where(id:LedgerEntry.where(budget_period_id:ids).select(:financial_transaction_id)).order(created_at: :desc,id: :desc)
      rows=scope.limit(@limit).offset(@history_offset).includes(:actor,ledger_entries:{budget_period: :budget_account}).map do |tx|
        # A scoped reader sees only the authorized legs; finance sees both legs.
        legs=tx.ledger_entries.select{|e|ids.include?(e.budget_period_id)}.map{|e|{account:e.budget_period.budget_account.name,account_id:e.budget_period.budget_account_id,delta:Finance::Money.string(e.funding_delta)}}
        {id:tx.id,kind:tx.kind,amount:Finance::Money.string(tx.amount),actor:tx.actor&.name,reason:tx.reason,created_at:tx.created_at,month:tx.month_start.strftime('%Y-%m'),legs:legs}
      end
      {rows:rows,total:scope.count,limit:@limit,offset:@history_offset}
    end
    def delegations
      scope=AllowanceDelegation.where(organization_id:@organization)
      scope=scope.where(manager_id:@actor.id) unless @policy.financial_operator?
      scope.order(created_at: :desc).limit(100).includes(:manager,:organizational_unit).map{|d|{id:d.id,manager:d.manager.name,unit:d.organizational_unit.name,maximum:Finance::Money.string(d.maximum_amount),from:d.effective_from_month.strftime('%Y-%m'),until:d.effective_until_month.strftime('%Y-%m'),revoked:!!d.revoked_at}}
    end
    def delegation_options
      return [] unless @policy.financial_operator?
      RoleAssignment.where(organization_id:@organization,role:'team_manager').includes(:user,:organizational_unit).map{|g|{manager_id:g.user_id,name:g.user.name,unit_id:g.organizational_unit_id,unit:g.organizational_unit.name}}
    end
    def project_contributors
      return [] unless @params['project_id'] && @policy.projects.exists?(id:@params['project_id'])
      scope=Analytics::Scope.new(@policy,{start:Controls.utc(@month).iso8601,end:Controls.utc(@month.next_month).iso8601,project_id:@params['project_id']})
      rows=Analytics::LedgerQuery.new(scope).groups('user_id::text AS user_id','user_id')
      names=User.where(organization_id:@organization,id:rows.map{|r|r['user_id']}).pluck(:id,:name).to_h
      rows.map{|r|r.merge('name'=>names[r['user_id']])}
    end
    def integer(key,default,range)
      value=@params.fetch(key,default.to_s).to_s
      raise Finance::Invalid,'Invalid pagination' unless value.match?(/\A\d+\z/) && range.cover?(value.to_i)
      value.to_i
    end
  end
end
