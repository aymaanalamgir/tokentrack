module Analytics
  class Report
    MONEY=%w[original_expenditure adjustments net_expenditure].freeze
    METRICS=%w[events priced_events unpriced_events input_tokens output_tokens cached_input_tokens active_users unsupported_profiles missing_rates pending_delivery].freeze
    def initialize(policy,params,client:UsageClient.new)
      @scope=Scope.new(policy,params);@policy=policy;@client=client;@ledger=LedgerQuery.new(@scope)
    end
    def call
      return perform if ApplicationRecord.connection.transaction_open?
      ApplicationRecord.transaction(isolation: :repeatable_read,requires_new:true) { perform }
    end
    def perform
      usage=@client.call(@scope.payload)
      if !@scope.filters.key?('start') && !@scope.filters.key?('end') && usage.dig('available_range','end')
        last=Time.parse(usage['available_range']['end']).utc.to_date.next_day.to_time.utc
        first=[last-30.days,Time.parse(usage['available_range']['start']).utc.beginning_of_day].max
        @scope=Scope.new(@policy,@scope.filters.merge('start'=>first.iso8601,'end'=>last.iso8601));@ledger=LedgerQuery.new(@scope)
        usage=@client.call(@scope.payload)
      end
      @available_range=usage['available_range']
      user_fin=@ledger.groups('user_id::text AS id','user_id')
      project_fin=@ledger.groups('project_id::text AS id','project_id')
      model_fin=@ledger.groups("payload->>'provider' AS provider,payload->>'model' AS model,payload->>'pricing_model' AS pricing_model,payload->>'pricing_provider' AS pricing_provider,payload->>'billing_basis' AS billing_basis",'1,2,3,4,5')
      tool_fin=@ledger.groups("payload->>'tool' AS id",'1')
      user_ids=usage['employees'].map{|r|r['id']}
      people=User.where(organization_id:@policy.organization_id,id:user_ids).pluck(:id,:name,:job_function).to_h{|id,name,job|[id,{name:name,job_function:job}]}
      # Group bounded SQL aggregates, never canonical event rows. Current primary
      # home teams label activity; charge-owner snapshots remain in ledger audit.
      homes=OrganizationalMembership.where(organization_id:@policy.organization_id,user_id:user_ids,is_primary:true).pluck(:user_id,:organizational_unit_id).to_h
      project_counts=ProjectMembership.active.where(organization_id:@policy.organization_id,user_id:user_ids,project_id:@policy.projects.select(:id)).group(:user_id).count
      employees=merge(usage['employees'],user_fin,['id']).map{|r|r.merge(people.fetch(r['id'],{})).merge('home_unit_id'=>homes[r['id']],'active_projects'=>project_counts.fetch(r['id'],0))}
      projects=merge(usage['projects'],project_fin,['id'])
      names=Project.where(organization_id:@policy.organization_id,id:projects.filter_map{|r|r['id']}).pluck(:id,:name).to_h
      projects.each{|r|r['name']=r['id'] ? names[r['id']] : 'Unassigned activity'}
      units=OrganizationalUnit.where(organization_id:@policy.organization_id).pluck(:id,:name,:parent_unit_id,:unit_type).map{|id,name,parent,type|{id:id,name:name,parent_id:parent,type:type}}
      teams=employees.group_by{|r|r['home_unit_id']}.map do |id,rows|
        row={'id'=>id,'name'=>units.find{|u|u[:id]==id}&.fetch(:name)||'Historical/current home unknown'}
        METRICS.each{|key|row[key]=rows.sum{|r|r[key].to_i}}
        MONEY.each{|key|row[key]=Finance::Money.string(rows.sum{|r|BigDecimal(r.fetch(key,'0'))})}
        row
      end
      total=usage['totals'].merge(@ledger.totals)
      total['pricing_coverage_percent']=percent(total['priced_events'].to_i,total['events'].to_i)
      total['total_tokens']=total['input_tokens'].to_i+total['output_tokens'].to_i
      total['unresolved_charge_owner']=PricedUsageReceipt.where(status:'unresolved').where(@scope.sql('business.priced_usage_receipts')).where(occurred_at:@scope.start...@scope.finish).count
      account_rows=accounts
      model_rows=merge(usage['models'],model_fin,%w[provider model pricing_provider pricing_model billing_basis])
      model_rows.each { |r| r['cost_share_percent']=percent(BigDecimal(r['net_expenditure']),BigDecimal(total['net_expenditure'])) }
      buckets=merge(usage['timeseries'],@ledger.timeseries,['bucket'])
      {schema_version:1,currency:'USD',summary:total,timeseries:fill_buckets(buckets),employees:employees,teams:teams,projects:projects,
       models:model_rows,tools:merge(usage['tools'],tool_fin,['id']),
       accounts:account_rows,budget:budget_summary(account_rows),comparisons:comparisons,transactions:@ledger.transactions,
       context:{scope:@policy.persona,organization_id:@policy.organization_id,identity_id:@policy.actor.id,scope_key:@policy.access_summary[:scope_key],start:@scope.start.iso8601,end:@scope.finish.iso8601,granularity:@scope.grain,available_range:usage['available_range'],units:authorized_units(units),
         projects:@policy.projects.order(:name).limit(100).pluck(:id,:name).map{|id,name|{id:id,name:name}},people:employees.map{|r|{id:r['id'],name:r[:name]||r['name']}},
         financial_label:'Modeled expenditure for priced, posted usage',team_basis:'Current primary home-team activity; not team-account charges',week_starts:'Monday',time_zone:'UTC'}}
    end
    def merge(usage,finance,keys)
      lookup=finance.index_by{|r|keys.map{|key|r[key]}}
      usage.map{|row|row.merge(lookup.fetch(keys.map{|k|row[k]},MONEY.to_h{|k|[k,'0']}))}
    end
    def percent(n,d) = d.positive? ? Finance::Money.string(BigDecimal(n.to_s)*100/BigDecimal(d.to_s)) : nil
    def authorized_units(units)
      return units if @policy.organization_viewer?
      units.select{|u|@policy.managed_unit_ids.include?(u[:id])}
    end
    def fill_buckets(rows)
      current=case @scope.grain;when 'week';@scope.start.beginning_of_week;when 'month';@scope.start.beginning_of_month;else;@scope.start.beginning_of_day;end
      index=rows.index_by{|r|Time.parse(r['bucket']).utc.to_date.to_s}
      result=[]
      while current<@scope.finish
        key=current.to_date.to_s
        result<<index.fetch(key, METRICS.to_h{|k|[k,0]}.merge(MONEY.to_h{|k|[k,'0']}).merge('bucket'=>current.iso8601))
        current=case @scope.grain;when 'week';current+7.days;when 'month';current.next_month;else;current+1.day;end
      end
      result
    end
    def accounts
      # Funding is a separate explicit authority. Organizational read or project
      # participation alone cannot expose account allocation.
      return nil unless @policy.budget_org_reader? || @policy.budget_unit_ids.any? || @policy.budget_project_ids.any?
      c=ApplicationRecord.connection
      query=BudgetPeriod.where(organization_id:@policy.organization_id).where('month_start>=? AND month_start<=?',@scope.start.to_date.beginning_of_month,(@scope.finish-0.000001).to_date.beginning_of_month)
      query=query.joins(:budget_account)
      unless @policy.budget_org_reader?
        query=query.where('budget_accounts.organizational_unit_id IN (?) OR budget_accounts.project_id IN (?)',@policy.budget_unit_ids,@policy.budget_project_ids)
      end
      query=query.where('budget_accounts.project_id=?',@scope.filters['project_id']) if @scope.filters['project_id']
      query=query.where('budget_accounts.organizational_unit_id=?',@scope.filters['organization_unit_id']) if @scope.filters['organization_unit_id']
      return nil if %w[user_id provider model tool].any?{|k|@scope.filters[k]} || (@scope.filters['project_id'] && @scope.filters['organization_unit_id'])
      relation=query.select('budget_periods.id')
      rows=c.select_all("SELECT a.id::text AS id,a.name,a.purpose,SUM(e.funding_delta) AS funding,SUM(e.expense_delta) AS expenditure FROM business.budget_accounts a JOIN business.budget_periods p ON p.budget_account_id=a.id LEFT JOIN business.ledger_entries e ON e.budget_period_id=p.id WHERE p.id IN (#{relation.to_sql}) GROUP BY a.id ORDER BY a.name").to_a
      rows.map do |r|
        funding=BigDecimal((r['funding']||0).to_s);expense=BigDecimal((r['expenditure']||0).to_s)
        r.merge('funding'=>Finance::Money.string(funding),'expenditure'=>Finance::Money.string(expense),'remaining'=>Finance::Money.string(funding-expense),'utilization_percent'=>percent(expense,funding),'over_budget'=>expense>funding,'period_basis'=>'Full UTC accounting months intersecting activity range')
      end
    end
    def budget_summary(rows)
      return nil unless rows
      funding=rows.sum{|r|BigDecimal(r['funding'])};expense=rows.sum{|r|BigDecimal(r['expenditure'])}
      {funding:Finance::Money.string(funding),expenditure:Finance::Money.string(expense),remaining:Finance::Money.string(funding-expense),utilization_percent:percent(expense,funding)}
    end
    def period_usage(from,to)
      return @client.call(@scope.payload(from,to)) if from>=Time.utc(2000)
      {'totals'=>METRICS.to_h{|key|[key,0]},'employees'=>[],'models'=>[],'tools'=>[],'projects'=>[]}
    end
    def comparisons
      %w[week month].to_h do |kind|
        available_start=@available_range['start'] && Time.parse(@available_range['start']).utc.beginning_of_day
        available_end=@available_range['end'] && Time.parse(@available_range['end']).utc.beginning_of_day+1.day
        anchor=available_end && available_end>@scope.start ? [@scope.finish,available_end].min : @scope.finish
        boundary=kind=='week' ? anchor.beginning_of_week : anchor.beginning_of_month
        current=kind=='week' ? boundary-7.days : boundary.prev_month
        previous=kind=='week' ? current-7.days : current.prev_month
        a=period_usage(current,boundary);b=period_usage(previous,current)
        now=a['totals']['input_tokens'].to_i+a['totals']['output_tokens'].to_i
        before=b['totals']['input_tokens'].to_i+b['totals']['output_tokens'].to_i
        financial_a=@ledger.totals(current,boundary);financial_b=@ledger.totals(previous,current)
        delta=now-before
        net_now=BigDecimal(financial_a['net_expenditure']);net_before=BigDecimal(financial_b['net_expenditure'])
        finance_change={current:financial_a['net_expenditure'],previous:financial_b['net_expenditure'],delta:Finance::Money.string(net_now-net_before),percent_change:net_before.zero? ? nil : Finance::Money.string((net_now-net_before)*100/net_before.abs),basis:net_before.negative? ? 'Absolute negative baseline; correction effects may dominate' : 'Previous complete period'}
        token_components=%w[input_tokens output_tokens cached_input_tokens].to_h{|key|[key,{current:a['totals'][key].to_i,previous:b['totals'][key].to_i,delta:a['totals'][key].to_i-b['totals'][key].to_i}]}
        contributors=%w[employees models tools projects].to_h do |dimension|
          key=dimension=='models' ? ->(r){[r['provider'],r['model']]} : ->(r){r['id']}
          old=b[dimension].group_by(&key).transform_values{|rows|rows.sum{|r|r['input_tokens'].to_i+r['output_tokens'].to_i}}
          changes=a[dimension].group_by(&key).map do |id,rows|
            row=rows.first
            new_tokens=rows.sum{|r|r['input_tokens'].to_i+r['output_tokens'].to_i}
            {id:id,label:row['model']||row['id'],tokens:new_tokens,previous_tokens:old.delete(id)||0}
          end
          old.each{|id,tokens|changes<<{id:id,label:id,tokens:0,previous_tokens:tokens}}
          changes.each{|r|r[:delta_tokens]=r[:tokens]-r[:previous_tokens]}
          [dimension,changes.sort_by{|r|-r[:delta_tokens].abs}.first(5)]
        end
        coverage=available_start && available_end && previous>=available_start && boundary<=available_end ? 'full_recorded_window' : 'partial_or_outside_recorded_window'
        finance_change[:percent_change]=nil unless coverage=='full_recorded_window'
        state=before.zero? ? (now.zero? ? 'no_activity' : 'new_activity') : 'comparable'
        [kind,{basis:'Complete UTC calendar boundaries, anchored no later than the recorded data end; incomplete recorded coverage suppresses percentages',current_start:current.iso8601,current_end:boundary.iso8601,previous_start:previous.iso8601,previous_end:current.iso8601,current_tokens:now,previous_tokens:before,delta_tokens:delta,recorded_coverage:coverage,percent_change:before.positive? && coverage=='full_recorded_window' ? Finance::Money.string(BigDecimal(delta.to_s)*100/before) : nil,state:state,finance_change:finance_change,token_components:token_components,current_finance:financial_a,previous_finance:financial_b,contributors:contributors}]
      end
    end
  end
end
