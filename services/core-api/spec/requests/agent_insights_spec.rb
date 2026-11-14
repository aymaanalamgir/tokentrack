require 'rails_helper'

RSpec.describe 'Authorized agent efficiency insights',type: :request do
  let(:usage){AgentUsageFake.new}
  let(:agent_id){SecureRandom.uuid}
  let(:other_id){SecureRandom.uuid}
  before{allow(Agents::UsageClient).to receive(:new).and_return(usage)}
  def insights(actor='olivia',params={});sign_in(actor);get '/api/v1/agents/insights',params:params end
  def run(id,agent:agent_id,at:'2026-11-20T10:00:00Z',outcome:'success',retried:false)={'source'=>'financial-spec','run_id'=>id,'agent_id'=>agent,'outcome'=>outcome,'retried'=>retried,'started_at'=>at}
  def post_cost(run_id,**overrides)=Finance::PricedUsagePosting.new.call(finance_payload.merge('agent_run_id'=>run_id).merge(overrides.stringify_keys))
  def types(agent=agent_id)=data['insights'].select{|i|i['agent_id']==agent}.map{|i|i['type']}
  # 20 baseline runs with two charges (0.213) and 20 current runs with three charges (0.3195): cost per success +50%.
  def cost_rise(current:metric_side(runs:20),baseline:metric_side(runs:20),state:'sufficient',models:[])
    finance_accounts
    usage.runs=(1..20).map{|n|run("b#{n}",at:'2026-11-05T10:00:00Z')}+(1..20).map{|n|run("c#{n}")}
    %w[b1 b2].each{|id|post_cost(id)}
    @current=%w[c1 c2 c3].map{|id|post_cost(id)}
    usage.insights=insights_response([insight_agent(agent_id,'Review',baseline,current,state:state,models:models)])
  end

  it 'requires an authenticated identity and rejects unknown or malformed filters' do
    get '/api/v1/agents/insights';expect(response).to have_http_status(:unauthorized)
    usage.insights=insights_response([])
    insights('olivia',organization_id:org.id);expect(response).to have_http_status(:bad_request)
    insights('olivia',compare:'decade');expect(response).to have_http_status(:bad_request)
    insights('olivia',insight_type:'vibes');expect(response).to have_http_status(:bad_request)
    insights('olivia',start:'2026-11-01T00:00:00Z');expect(response).to have_http_status(:bad_request)
    insights('olivia',severity:['warning']);expect(response).to have_http_status(:bad_request)
    insights;expect(response).to have_http_status(:ok)
    expect(data).to include('schema_version'=>1,'analysis_version'=>1,'currency'=>'USD','insights'=>[],'thresholds'=>AgentInsightHelpers::THRESHOLDS)
    expect(data['summary']).to include('findings'=>0,'agents_analyzed'=>0)
    expect(data['limitations']).to be_present
  end

  it 'detects a cost-per-success rise from corrected ledger cost and withdraws it when a correction removes the rise' do
    cost_rise
    insights
    finding=data['insights'].sole
    expect(finding).to include('type'=>'cost_per_success_increase','severity'=>'critical','evidence_quality'=>'sufficient','baseline'=>'0.01065','current'=>'0.015975','percent_change'=>'50','id'=>"cost-per-success-increase-#{agent_id}",'agent_name'=>'Review')
    expect(finding['suggested_action']).to include('cost-driver breakdown')
    expect(finding.dig('evidence','current')).to include('corrected_modeled_cost'=>'0.3195','adjustments'=>'0','cost_completeness'=>'complete')
    expect(finding['drilldown']).to eq('agent_id'=>agent_id,'start'=>'2026-11-15T00:00:00Z','end'=>'2026-12-01T00:00:00Z')
    Finance::Operations.new(person('olivia')).correct(original_id:@current.first[:financial_transaction_id],amount:'0.05',key:'insight-correction',reason:'Insight correction')
    insights
    expect(data['insights']).to eq([])
    agent=data['agents'].sole
    expect(agent['current']).to include('corrected_modeled_cost'=>'0.263','original_modeled_cost'=>'0.3195','adjustments'=>'-0.0565','cost_per_success'=>'0.01315')
    expect(agent.dig('decomposition','associated_factors').find{|f|f['metric']=='adjustments'}).to include('baseline'=>'0','current'=>'-0.0565')
  end

  it 'reconciles every displayed total to the ledger exactly once and splits the change without residue' do
    cost_rise
    usage.insights['agents']<<insight_agent(other_id,'Indexer',metric_side(runs:10),metric_side(runs:30))
    usage.runs+=(1..10).map{|n|run("ob#{n}",agent:other_id,at:'2026-11-05T10:00:00Z')}+(1..30).map{|n|run("oc#{n}",agent:other_id)}
    post_cost('ob1');%w[oc1 oc2 oc3].each{|id|post_cost(id)}
    insights
    agents=data['agents'].to_h{|a|[a['name'],a]}
    %w[baseline current].each do |period|
      expect(agents.values.sum{|a|BigDecimal(a[period]['corrected_modeled_cost'])}).to eq(BigDecimal(data['summary'][period]['corrected_modeled_cost']))
    end
    expect(BigDecimal(data['summary']['baseline']['corrected_modeled_cost'])+BigDecimal(data['summary']['current']['corrected_modeled_cost'])).to eq(LedgerEntry.joins(:financial_transaction).where(financial_transactions:{organization_id:org.id}).sum(:expense_delta))
    # Volume tripled at an unchanged cost per run: the whole change is volume, and no inefficiency is reported.
    split=agents['Indexer']['decomposition']
    expect(split['cost']).to include('baseline'=>'0.1065','current'=>'0.3195','delta'=>'0.213')
    expect(split['exact']).to include('volume_effect'=>'0.213','per_run_cost_effect'=>'0')
    expect(types(other_id)).to eq([])
    review=agents['Review']['decomposition']
    expect(BigDecimal(review.dig('exact','volume_effect'))+BigDecimal(review.dig('exact','per_run_cost_effect'))).to eq(BigDecimal(review.dig('cost','delta')))
    expect(review['associated_factors'].map{|f|f['attribution']}.uniq).to eq(['associated'])
    expect(data.to_json).not_to match(/Infinity|NaN/)
    expect(data['summary']['cost_change']).to include('baseline'=>'0.3195','current'=>'0.639','percent_change'=>'100')
  end

  it 'qualifies cost findings when financial coverage is incomplete and discloses the gap' do
    cost_rise(current:metric_side(runs:20,unpriced:4))
    insights
    rise=data['insights'].find{|i|i['type']=='cost_per_success_increase'}
    expect(rise).to include('severity'=>'info','evidence_quality'=>'incomplete_cost_data','evidence_quality_label'=>'Incomplete cost data')
    expect(rise['quality_reason']).to include('known posted cost only')
    gap=data['insights'].find{|i|i['type']=='pricing_coverage_gap'}
    expect(gap).to include('severity'=>'warning','current'=>'80.0','evidence_quality'=>'incomplete_cost_data')
    expect(gap.dig('evidence','current')).to include('unpriced_events'=>4)
    expect(gap['suggested_action']).to include('Resolve unsupported pricing profiles')
    expect(data.dig('coverage','current')).to include('cost_completeness'=>'partial_unpriced_or_unposted','unpriced_events'=>4)
    expect(data['agents'].sole.dig('decomposition','basis')).to eq('known_posted_cost_only')
    insights('olivia',evidence_quality:'sufficient');expect(data['insights']).to eq([]);expect(data['summary']).to include('findings'=>0,'total_findings'=>2)
    insights('olivia',insight_type:'pricing_coverage_gap');expect(types).to eq(['pricing_coverage_gap'])
  end

  it 'does not assert cost anomalies on sparse or limited samples or missing baselines' do
    cost_rise(state:'insufficient_data');insights;expect(data['insights']).to eq([]);expect(data['summary']['agents_without_comparison']).to eq(1)
    usage.insights['agents'][0]['evidence_state']='unsupported_comparison';insights;expect(data['insights']).to eq([])
    usage.insights['agents'][0]['evidence_state']='limited_sample';insights
    expect(data['insights'].sole).to include('type'=>'cost_per_success_increase','severity'=>'info','evidence_quality'=>'limited_sample')
  end

  it 'reports failed-run spend by logical outcome without inventing attempt-level cost' do
    finance_accounts
    usage.runs=(1..20).map{|n|run("f#{n}",outcome:n<=5 ? 'failure' : 'success',retried:n==6)}
    %w[f1 f2 f6 f7 f8].each{|id|post_cost(id)}
    usage.insights=insights_response([insight_agent(agent_id,'Review',metric_side(runs:0),metric_side(runs:20,successes:15,failed:5),state:'unsupported_comparison')])
    insights
    finding=data['insights'].sole
    expect(finding).to include('type'=>'failed_run_spend','severity'=>'warning','current'=>'40','baseline'=>nil,'percent_change'=>nil)
    expect(finding.dig('evidence','categories')).to eq('failed_logical_runs'=>'0.213','successful_runs_that_required_retries'=>'0.1065','failed_retry_attempts'=>nil)
    expect(finding['drilldown']).to include('outcome'=>'failure')
    expect(finding['limitation']).to include('cannot be costed separately')
  end

  it 'describes model cost concentration with a clearly hypothetical rate-only scenario, and never for a single model' do
    scenario={'label'=>'Hypothetical rate-only comparison','recorded_pricing_model'=>'anthropic/claude-sonnet-4-6','alternative_pricing_model'=>'openai/gpt-5.4-mini','modeled_cost_at_recorded_rates'=>'0.396','modeled_cost_at_alternative_rates'=>'0.1065','modeled_difference'=>'0.2895'}
    models=[{'provider'=>'anthropic','model'=>'claude-sonnet-4-6','pricing_provider'=>'anthropic','pricing_model'=>'claude-sonnet-4-6','baseline'=>nil,'current'=>{'events'=>4,'priced_events'=>4,'token_share_percent'=>'80'},'rate_schedule_changed'=>false,'rate_only_scenario'=>scenario},
            {'provider'=>'openai','model'=>'gpt-5.4-mini','pricing_provider'=>'openai','pricing_model'=>'gpt-5.4-mini','baseline'=>nil,'current'=>{'events'=>1,'priced_events'=>1,'token_share_percent'=>'20'},'rate_schedule_changed'=>false,'rate_only_scenario'=>nil}]
    finance_accounts
    usage.runs=(1..20).map{|n|run("m#{n}")}
    %w[m1 m2 m3 m4].each{|id|post_cost(id,provider:'anthropic',model:'claude-sonnet-4-6')};post_cost('m5')
    usage.insights=insights_response([insight_agent(agent_id,'Summarizer',metric_side(runs:0),metric_side(runs:20),state:'unsupported_comparison',models:models)])
    insights
    finding=data['insights'].sole
    expect(finding).to include('type'=>'model_cost_concentration','severity'=>'info','current'=>'80')
    expect(finding['finding']).to include('anthropic/claude-sonnet-4-6 accounts for 80.0%')
    expect(finding['limitation']).to include('not evidence that the model is inefficient')
    expect(finding.dig('evidence','savings_scenario')).to include('label'=>'Hypothetical rate-only comparison','not_ledger_expenditure'=>true,'assumptions'=>['Same input tokens','Same output tokens','Same cached-input tokens'])
    expect(finding.dig('evidence','savings_scenario','does_not_account_for')).to include('Response quality','Changes in tokenization')
    usage.insights['agents'][0]['models']=models.first(1);usage.runs=usage.runs.reject{|r|r['run_id']=='m5'}
    insights;expect(data['insights']).to eq([])
  end

  it 'passes operational findings through with wording, coverage and neutral associated observations' do
    cost_rise(current:metric_side(runs:20,retried:5),baseline:metric_side(runs:20,retried:1))
    usage.insights['insights']=[{'type'=>'retry_increase','agent_id'=>agent_id,'metric'=>'retry_rate_percent','unit'=>'percent','baseline'=>'5','current'=>'25','absolute_change'=>'20','percent_change'=>'400','threshold'=>{'kind'=>'points','value'=>'10'},'severity'=>'critical','evidence_quality'=>'sufficient','quality_reason'=>'20 current and 20 comparison runs.','sample_size'=>{'baseline_runs'=>20,'current_runs'=>20,'basis'=>'runs'},'evidence'=>{'current'=>{'retried_runs'=>5}}}]
    insights('olivia',insight_type:'retry_increase')
    finding=data['insights'].sole
    expect(finding).to include('finding'=>'Retry rate increased 20.0 percentage points (5.0% to 25.0%).','status'=>'open','financial_coverage'=>{'baseline'=>'complete','current'=>'complete'})
    expect(finding['suggested_action']).to start_with('Inspect recent provider-error and timeout patterns before changing retry policy')
    expect(finding['drilldown']).to include('retried'=>'true')
    expect(finding['associated'].find{|a|a['metric']=='cost_per_success'}).to include('label'=>'Cost per successful run','percent_change'=>'50')
    expect(finding['limitation']).to include('no cost is attributed to individual retries')
  end

  it 'derives the population from AccessPolicy for every persona and never from request parameters' do
    usage.insights=insights_response([])
    payload=->{usage.calls.reverse.find{|path,_|path=='agent-insights'}.last}
    insights('olivia');expect(payload.call).to include(organization_id:org.id,all_users:true,scope_users:[],start:nil,end:nil,compare:'previous_period')
    insights('jordan');expect(payload.call).to include(all_users:false,scope_users:[person('jordan').id],scope_projects:[])
    insights('marcus');manager=payload.call
    expect(manager[:all_users]).to be(false);expect(manager[:scope_users]).to match_array(AccessPolicy.new(person('marcus')).managed_user_ids);expect(manager[:scope_projects]).to eq([project('developer-productivity').id])
    expect(manager[:scope_users]).not_to include(person('priya').id)
    insights('priya');expect(payload.call).to include(scope_users:[person('priya').id]);expect(payload.call[:scope_projects]).to match_array([project('fraud-detection').id,project('customer-analytics').id])
    insights('maya','northstar-labs') rescue nil
    sign_in('maya','northstar-labs');get '/api/v1/agents/insights'
    expect(payload.call[:organization_id]).to eq(org('northstar-labs').id);expect(payload.call[:organization_id]).not_to eq(org.id)
    expect(data.dig('scope','organization_id')).to eq(org('northstar-labs').id)
  end

  it 'denies agents, projects and employees outside the requester scope' do
    usage.insights=insights_response([],visible:false)
    insights('jordan',agent_id:agent_id);expect(response).to have_http_status(:not_found)
    usage.insights=insights_response([])
    insights('jordan',user_id:person('olivia').id);expect(response).to have_http_status(:not_found)
    hidden=(Project.where(organization:org).pluck(:id)-AccessPolicy.new(person('sofia')).projects.pluck(:id)).first
    expect(hidden).to be_present
    insights('sofia',project_id:hidden);expect(response).to have_http_status(:not_found)
    insights('olivia',project_id:Project.find_by!(organization:org('northstar-labs')).id);expect(response).to have_http_status(:not_found)
    insights('priya',project_id:project('fraud-detection').id);expect(response).to have_http_status(:ok)
    expect(usage.calls.last.last).to include(project_id:project('fraud-detection').id)
  end

  it 'scopes ledger cost to the requester even if a cohort row lies outside their population' do
    cost_rise
    Agents::LedgerCosts.new(Agents::Scope.new(AccessPolicy.new(person('sofia')),{},keys:Agents::Scope::INSIGHT_KEYS)).call(usage.runs).then{|costs|expect(costs).to eq({})}
    expect(Agents::LedgerCosts.new(Agents::Scope.new(AccessPolicy.new(person('jordan')),{},keys:Agents::Scope::INSIGHT_KEYS)).call(usage.runs).size).to eq(5)
  end

  it 'returns a retryable error instead of partial or estimated findings' do
    allow(usage).to receive(:call).and_raise(Agents::Unavailable)
    insights;expect(response).to have_http_status(:service_unavailable);expect(json.dig('error','code')).to eq('agent_analytics_unavailable')
  end
end
