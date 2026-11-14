module Agents
  class Report
    def initialize(policy,params,client:UsageClient.new);@policy=policy;@scope=Scope.new(policy,params);@client=client end
    def call
      usage=@client.call(@scope.payload)
      # Whole-cohort cost is aggregated page by page (no 5,000-run cap); the visible run page is priced directly.
      costs=CostAggregator.new(@scope,client:@client).call(@scope.base_payload);page=LedgerCosts.new(@scope).call(usage['runs']['rows'])
      usage['runs']['rows'].each{|run|run['corrected_modeled_cost']=Finance::Money.string(page.dig([run['source'],run['run_id']],:net)||0)}
      usage['agents'].each{|agent|agent['corrected_modeled_cost']=Finance::Money.string(costs.agents.key?(agent['id']) ? costs.agents[agent['id']][:cost] : 0)}
      total=costs.total[:cost];successes=usage['totals']['successful_runs'].to_i
      usage['totals']['corrected_modeled_cost']=Finance::Money.string(total)
      usage['totals']['cost_per_success']=successes.positive? ? Finance::Money.string(total/successes) : nil
      usage['totals']['average_successful_run_cost']=successes.positive? ? Finance::Money.string(costs.total[:success_cost]/successes) : nil
      usage['totals']['cost_completeness']=usage['totals']['unpriced_events'].to_i.zero?&&usage['totals']['pending_delivery'].to_i.zero? ? 'complete' : 'partial_unpriced_or_unposted'
      usage['totals']['costed_cohort_runs']=costs.total[:runs]
      ids=usage.dig('runs','rows').flat_map{|r|[r['user_id'],r['project_id']]}.compact.uniq
      people=User.where(organization_id:@policy.organization_id,id:ids).pluck(:id,:name).to_h;projects=Project.where(organization_id:@policy.organization_id,id:ids).pluck(:id,:name).to_h
      usage['runs']['rows'].each{|r|r['user_name']=people[r['user_id']];r['project_name']=projects[r['project_id']]}
      usage.merge('schema_version'=>1,'currency'=>'USD','context'=>{'scope'=>@policy.persona,'organization_id'=>@policy.organization_id,'identity_id'=>@policy.actor.id,'scope_key'=>@policy.access_summary[:scope_key],'start'=>@scope.start.iso8601,'end'=>@scope.finish.iso8601,'projects'=>@policy.projects.order(:name).limit(100).pluck(:id,:name).map{|id,name|{'id'=>id,'name'=>name}},'money_basis'=>'Corrected posted ledger expenditure; partial when linked usage is unpriced or pending delivery'})
    end
  end
end
