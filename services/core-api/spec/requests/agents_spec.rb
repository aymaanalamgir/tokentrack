require 'rails_helper'
require 'benchmark'

RSpec.describe 'Authorized agent execution analytics',type: :request do
  let(:filters){{start:'2026-11-01T00:00:00Z',end:'2026-12-01T00:00:00Z'}}
  let(:run_id){'agent-run-1'}
  let(:agent_id){SecureRandom.uuid}
  let(:metric){{'runs'=>1,'successful_runs'=>1,'failed_runs'=>0,'cancelled_runs'=>0,'incomplete_runs'=>0,'retried_runs'=>1,'attempts'=>2,'retries'=>1,'average_retries'=>'1','average_duration_seconds'=>'42','retry_rate_percent'=>'100','input_tokens'=>'100000','output_tokens'=>'10000','cached_input_tokens'=>'20000','usage_events'=>1,'priced_events'=>1,'unpriced_events'=>0,'pending_delivery'=>0}}
  let(:usage){AgentUsageFake.new}
  before do
    usage.report={'schema_version'=>2,'available_range'=>{'start'=>'2026-11-15T14:00:00Z','end'=>'2026-11-15T14:00:00Z'},'totals'=>metric,'timeseries'=>[metric.merge('bucket'=>'2026-11-15')],
       'agents'=>[metric.merge('id'=>agent_id,'agent_key'=>'review','name'=>'Review','workflow_type'=>'code-review')],
       'runs'=>{'rows'=>[{'id'=>SecureRandom.uuid,'agent_id'=>agent_id,'agent_key'=>'review','agent_name'=>'Review','workflow_type'=>'code-review','source'=>'financial-spec','run_id'=>run_id,'user_id'=>person('jordan').id,'project_id'=>project.id,'started_at'=>'2026-11-15T14:00:00Z','completed_at'=>'2026-11-15T14:00:42Z','status'=>'completed','outcome'=>'success','attempts'=>2,'retries'=>1,'duration_seconds'=>'42','input_tokens'=>'100000','output_tokens'=>'10000','cached_input_tokens'=>'20000','usage_events'=>1,'priced_events'=>1,'unpriced_events'=>0,'pending_delivery'=>0,'attempt_records'=>[]}],'total'=>1,'limit'=>25,'offset'=>0}}
    usage.runs=[{'source'=>'financial-spec','run_id'=>run_id,'outcome'=>'success','agent_id'=>agent_id,'retried'=>true,'started_at'=>'2026-11-15T14:00:00Z'}]
    allow(Agents::UsageClient).to receive(:new).and_return(usage)
  end
  def report(actor='olivia',extra={});sign_in(actor);get '/api/v1/agents',params:filters.merge(extra) end
  it 'requires an authenticated identity' do
    get '/api/v1/agents',params:filters
    expect(response).to have_http_status(:unauthorized)
  end
  it 'uses corrected posted ledger cost and retains explicit retries and outcomes' do
    finance_accounts
    payload=finance_payload.merge('agent_run_id'=>run_id)
    posted=Finance::PricedUsagePosting.new.call(payload)
    Finance::Operations.new(person('olivia')).correct(original_id:posted[:financial_transaction_id],amount:'0.1',key:'agent-correction',reason:'Agent reporting correction')
    report
    expect(response).to have_http_status(:ok)
    expect(data['totals']).to include('corrected_modeled_cost'=>'0.1','cost_per_success'=>'0.1','average_successful_run_cost'=>'0.1','retries'=>1)
    expect(data.dig('runs','rows',0,'corrected_modeled_cost')).to eq('0.1')
    expect(data.dig('agents',0,'corrected_modeled_cost')).to eq('0.1')
    expect(usage.calls.map(&:first)).to eq(%w[agent-analytics agent-cohort])
    expect(usage.calls.first.last[:organization_id]).to eq(org.id)
  end
  it 'aggregates corrected cost over a cohort larger than the former 5,000-run cap without truncation' do
    finance_accounts
    usage.runs=(1..6_000).map{|n|{'source'=>'financial-spec','run_id'=>format('bulk-%05d',n),'outcome'=>n<=4_500 ? 'success' : 'failure','agent_id'=>agent_id,'retried'=>false,'started_at'=>(Time.utc(2026,11,2)+n*60).iso8601}}
    usage.report['totals']=metric.merge('runs'=>6_000,'successful_runs'=>4_500,'failed_runs'=>1_500)
    first=Finance::PricedUsagePosting.new.call(finance_payload.merge('agent_run_id'=>'bulk-00001'))
    Finance::PricedUsagePosting.new.call(finance_payload.merge('agent_run_id'=>'bulk-05999'))
    Finance::PricedUsagePosting.new.call(finance_payload.merge('agent_run_id'=>'bulk-05999'))
    Finance::Operations.new(person('olivia')).correct(original_id:first[:financial_transaction_id],amount:'0.05',key:'bulk-correction',reason:'Large cohort correction')
    elapsed=Benchmark.realtime{report}
    puts "PERF Rails cost enrichment for 6,000 runs in 6 pages: #{(elapsed*1000).round} ms"
    expect(response).to have_http_status(:ok)
    cohort=usage.calls.select{|path,_|path=='agent-cohort'}
    expect(cohort.size).to eq(7)
    expect(cohort.map{|_,payload|payload[:batch]}.uniq).to eq([1000])
    expect(data['totals']).to include('corrected_modeled_cost'=>'0.263','costed_cohort_runs'=>6_000,'cost_per_success'=>Finance::Money.string(BigDecimal('0.263')/4_500),'average_successful_run_cost'=>Finance::Money.string(BigDecimal('0.05')/4_500))
    expect(BigDecimal(data['totals']['corrected_modeled_cost'])).to eq(LedgerEntry.joins(:financial_transaction).where(financial_transactions:{organization_id:org.id}).where.not(expense_delta:0).sum(:expense_delta))
    expect{Agents::LedgerCosts.new(Agents::Scope.new(AccessPolicy.new(person('olivia')),filters)).call(usage.runs.first(1_001))}.to raise_error(ArgumentError)
  end
  it 'supplies only policy population and rejects unrelated filters' do
    scope=Agents::Scope.new(AccessPolicy.new(person('jordan')),filters)
    expect(scope.payload[:all_users]).to be(false)
    expect(scope.payload[:scope_users]).to eq([person('jordan').id])
    expect(scope.payload[:scope_projects]).to eq([])
    report('jordan',user_id:person('olivia').id);expect(response).to have_http_status(:not_found)
    report('olivia',organization_id:org.id);expect(response).to have_http_status(:bad_request)
    report('olivia',outcome:'invented');expect(response).to have_http_status(:bad_request)
  end
  it 'returns a retryable error instead of estimated data' do
    allow(usage).to receive(:call).and_raise(Agents::Unavailable)
    report
    expect(response).to have_http_status(:service_unavailable)
    expect(json.dig('error','code')).to eq('agent_analytics_unavailable')
  end
end
