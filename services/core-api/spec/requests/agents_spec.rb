require 'rails_helper'

RSpec.describe 'Authorized agent execution analytics',type: :request do
  let(:filters){{start:'2026-11-01T00:00:00Z',end:'2026-12-01T00:00:00Z'}}
  let(:run_id){'agent-run-1'}
  let(:agent_id){SecureRandom.uuid}
  let(:metric){{'runs'=>1,'successful_runs'=>1,'failed_runs'=>0,'cancelled_runs'=>0,'incomplete_runs'=>0,'retried_runs'=>1,'attempts'=>2,'retries'=>1,'average_retries'=>'1','average_duration_seconds'=>'42','retry_rate_percent'=>'100','input_tokens'=>'100000','output_tokens'=>'10000','cached_input_tokens'=>'20000','usage_events'=>1,'priced_events'=>1,'unpriced_events'=>0,'pending_delivery'=>0}}
  before do
    allow_any_instance_of(Agents::UsageClient).to receive(:call) do |_,payload|
      expect(payload[:organization_id]).to eq(org.id)
      {'schema_version'=>1,'available_range'=>{'start'=>'2026-11-15T14:00:00Z','end'=>'2026-11-15T14:00:00Z'},'totals'=>metric,'timeseries'=>[metric.merge('bucket'=>'2026-11-15')],
       'agents'=>[metric.merge('id'=>agent_id,'agent_key'=>'review','name'=>'Review','workflow_type'=>'code-review')],
       'runs'=>{'rows'=>[{'id'=>SecureRandom.uuid,'agent_id'=>agent_id,'agent_key'=>'review','agent_name'=>'Review','workflow_type'=>'code-review','source'=>'financial-spec','run_id'=>run_id,'user_id'=>person('jordan').id,'project_id'=>project.id,'started_at'=>'2026-11-15T14:00:00Z','completed_at'=>'2026-11-15T14:00:42Z','status'=>'completed','outcome'=>'success','attempts'=>2,'retries'=>1,'duration_seconds'=>'42','input_tokens'=>'100000','output_tokens'=>'10000','cached_input_tokens'=>'20000','usage_events'=>1,'priced_events'=>1,'unpriced_events'=>0,'pending_delivery'=>0,'attempt_records'=>[]}],'total'=>1,'limit'=>25,'offset'=>0},
       'cohort_runs'=>[{'source'=>'financial-spec','run_id'=>run_id,'outcome'=>'success','agent_id'=>agent_id}]}
    end
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
    allow_any_instance_of(Agents::UsageClient).to receive(:call).and_raise(Agents::Unavailable)
    report
    expect(response).to have_http_status(:service_unavailable)
    expect(json.dig('error','code')).to eq('agent_analytics_unavailable')
  end
end
