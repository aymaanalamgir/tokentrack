module Agents
  class Report
    def initialize(policy,params,client:UsageClient.new);@policy=policy;@scope=Scope.new(policy,params);@client=client end
    def call
      usage=@client.call(@scope.payload);costs=LedgerCosts.new(@scope).call(usage['cohort_runs'])
      usage['runs']['rows'].each{|run|run['corrected_modeled_cost']=costs.fetch([run['source'],run['run_id']],'0')}
      by_agent=usage['cohort_runs'].group_by{|r|r['agent_id']}.transform_values{|rows|rows.sum{|r|BigDecimal(costs.fetch([r['source'],r['run_id']],'0'))}}
      usage['agents'].each{|agent|agent['corrected_modeled_cost']=Finance::Money.string(by_agent.fetch(agent['id'],0))}
      total=costs.values.sum{|v|BigDecimal(v)};successes=usage['totals']['successful_runs'].to_i
      successful_cost=usage['cohort_runs'].select{|r|r['outcome']=='success'}.sum{|r|BigDecimal(costs.fetch([r['source'],r['run_id']],'0'))}
      usage['totals']['corrected_modeled_cost']=Finance::Money.string(total)
      usage['totals']['cost_per_success']=successes.positive? ? Finance::Money.string(total/successes) : nil
      usage['totals']['average_successful_run_cost']=successes.positive? ? Finance::Money.string(successful_cost/successes) : nil
      usage['totals']['cost_completeness']=usage['totals']['unpriced_events'].to_i.zero?&&usage['totals']['pending_delivery'].to_i.zero? ? 'complete' : 'partial_unpriced_or_unposted'
      ids=usage.dig('runs','rows').flat_map{|r|[r['user_id'],r['project_id']]}.compact.uniq
      people=User.where(organization_id:@policy.organization_id,id:ids).pluck(:id,:name).to_h;projects=Project.where(organization_id:@policy.organization_id,id:ids).pluck(:id,:name).to_h
      usage['runs']['rows'].each{|r|r['user_name']=people[r['user_id']];r['project_name']=projects[r['project_id']]}
      usage.delete('cohort_runs')
      usage.merge('currency'=>'USD','context'=>{'scope'=>@policy.persona,'organization_id'=>@policy.organization_id,'identity_id'=>@policy.actor.id,'scope_key'=>@policy.access_summary[:scope_key],'start'=>@scope.start.iso8601,'end'=>@scope.finish.iso8601,'projects'=>@policy.projects.order(:name).limit(100).pluck(:id,:name).map{|id,name|{'id'=>id,'name'=>name}},'money_basis'=>'Corrected posted ledger expenditure; partial when linked usage is unpriced or pending delivery'})
    end
  end
end
