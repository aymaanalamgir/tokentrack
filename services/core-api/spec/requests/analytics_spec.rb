require 'rails_helper'

RSpec.describe 'Authorized analytics',type: :request do
  let(:metric) { {'events'=>2,'priced_events'=>1,'unpriced_events'=>1,'input_tokens'=>'100000','output_tokens'=>'10000','cached_input_tokens'=>'20000','active_users'=>1,'unsupported_profiles'=>1,'missing_rates'=>0,'pending_delivery'=>0} }
  let(:filters) { {start:'2026-11-01T00:00:00Z',end:'2026-12-01T00:00:00Z'} }
  before do
    allow_any_instance_of(Analytics::UsageClient).to receive(:call) do |_,payload|
      row=metric.merge('id'=>person('jordan').id)
      {'schema_version'=>1,'available_range'=>{'start'=>'2026-11-15T14:30:00Z','end'=>'2026-11-15T14:30:00Z'},'totals'=>metric,'employees'=>[row],'projects'=>[metric.merge('id'=>project.id)],'models'=>[metric.merge('provider'=>'openai','model'=>'gpt-5.4-mini','pricing_model'=>'gpt-5.4-mini','pricing_provider'=>'openai','billing_basis'=>'synthetic_standard_cache_read')],'tools'=>[metric.merge('id'=>'coding-assistant')],'timeseries'=>[metric.merge('bucket'=>'2026-11-15T00:00:00Z')]}
    end
  end
  def report(actor='olivia',extra={})
    sign_in(actor)
    get '/api/v1/analytics',params:filters.merge(extra)
  end
  it 'requires an authenticated identity' do
    get '/api/v1/analytics',params:filters
    expect(response).to have_http_status(:unauthorized)
  end
  it 'aggregates exact corrected ledger expense and excludes funding transfers' do
    finance_accounts
    posted=Finance::PricedUsagePosting.new.call(finance_payload)
    Finance::Operations.new(person('olivia')).correct(original_id:posted[:financial_transaction_id],amount:'0.1',key:'analytics-correction',reason:'Reporting correction test')
    report
    expect(response).to have_http_status(:ok)
    expect(data['summary']).to include('original_expenditure'=>'0.1065','adjustments'=>'-0.0065','net_expenditure'=>'0.1','events'=>2,'unpriced_events'=>1,'pricing_coverage_percent'=>'50')
    expect(data['projects'].first['net_expenditure']).to eq('0.1')
    expect(data['models'].first['net_expenditure']).to eq('0.1')
    expect(data['tools'].first['net_expenditure']).to eq('0.1')
    expect(data['employees'].first['net_expenditure']).to eq('0.1')
    expect(data['teams'].sum{|r|BigDecimal(r['net_expenditure'])}).to eq(BigDecimal('0.1'))
    expect(data['budget']['funding']).to eq('100')
    expect(data['budget']['expenditure']).to eq('0.1')
    expect(data['timeseries'].size).to eq(30)
    expect(data['timeseries'].sum{|r|BigDecimal(r['net_expenditure'])}).to eq(BigDecimal('0.1'))
  end
  it 'uses the project charge owner instead of summing employee/team dimensions' do
    accounts=finance_accounts
    Finance::PricedUsagePosting.new.call(finance_payload)
    report('olivia',{project_id:project.id})
    expect(data['accounts'].map{|r|r['id']}).to eq([accounts['project'].id])
    expect(data['budget']['expenditure']).to eq('0.1065')
    expect(data['summary']['net_expenditure']).to eq('0.1065')
  end
  it 'allows budget reads only through explicit read grants, never manager titles' do
    finance_accounts
    report('marcus')
    expect(data['accounts']).to be_nil
    RoleAssignment.create!(organization:org,user:person('marcus'),role:'team_budget_reader',scope_type:'unit',organizational_unit:team('platform'))
    report('marcus')
    expect(data['accounts'].map{|r|r['purpose']}).to eq(['unit'])
    expect(AccessPolicy.new(person('marcus')).financial_operator?).to be(false)
  end
  it 'restricts employee ledger data to self even when a project filter is visible' do
    finance_accounts
    Finance::PricedUsagePosting.new.call(finance_payload(user:person('sofia')))
    report('jordan',{project_id:project.id})
    expect(data['summary']['net_expenditure']).to eq('0')
    expect(data['budget']).to be_nil
  end
  it 'keeps project leads restricted to led-project activity when drilling into a contributor' do
    finance_accounts
    Finance::PricedUsagePosting.new.call(finance_payload)
    scope=Analytics::Scope.new(AccessPolicy.new(person('priya')),filters.merge(user_id:person('jordan').id))
    expect(scope.payload[:all_users]).to be(false)
    expect(scope.payload[:scope_users]).not_to include(person('jordan').id)
    expect(scope.payload[:scope_projects]).to include(project.id)
    report('priya',{user_id:person('jordan').id})
    expect(response).to have_http_status(:ok)
    expect(data['summary']['net_expenditure']).to eq('0.1065')
  end
  it 'does not send directory colleagues as private usage scope' do
    scope=Analytics::Scope.new(AccessPolicy.new(person('jordan')),filters)
    expect(scope.payload[:scope_users]).to eq([person('jordan').id])
    expect(scope.payload[:scope_projects]).to eq([])
  end
  it 'rejects foreign tenants and unrelated employee, project and team filters' do
    report('jordan',{user_id:person('maya','northstar-labs').id});expect(response).to have_http_status(:not_found)
    report('jordan',{user_id:person('olivia').id});expect(response).to have_http_status(:not_found)
    report('jordan',{organization_unit_id:team('platform').id});expect(response).to have_http_status(:not_found)
    foreign=Project.find_by!(organization:org('northstar-labs'))
    report('olivia',{project_id:foreign.id});expect(response).to have_http_status(:not_found)
  end
  it 'rejects invalid ranges, non UTC timestamps, granularity, identifiers and unknown filters' do
    [{start:'2020-01-01T00:00:00Z'},{end:'2026-10-01T00:00:00Z'},{start:'2026-11-01'},{granularity:'hour'},{user_id:'bad'},{organization_id:org.id},{limit:'101'},{provider:"';DROP TABLE usage_events"}].each do |extra|
      report('olivia',extra);expect(response).to have_http_status(:bad_request)
    end
  end
  it 'uses complete Monday weeks and complete calendar months with explicit zero baseline states' do
    report
    expect(data.dig('comparisons','week','current_start')).to eq('2026-11-09T00:00:00Z')
    expect(data.dig('comparisons','week','current_end')).to eq('2026-11-16T00:00:00Z')
    expect(data.dig('comparisons','month','current_start')).to eq('2026-10-01T00:00:00Z')
    expect(data.dig('comparisons','month','previous_start')).to eq('2026-09-01T00:00:00Z')
    expect(data['comparisons']['week']['percent_change']).to be_nil
    expect(data['comparisons']['week']['recorded_coverage']).to eq('partial_or_outside_recorded_window')
  end
  it 'reports a genuine zero baseline as new activity without infinite percentages' do
    allow_any_instance_of(Analytics::UsageClient).to receive(:call) do |_,payload|
      m=metric.dup
      m=m.transform_values{0} if payload[:start]=='2026-10-01T00:00:00Z'
      {'schema_version'=>1,'available_range'=>{'start'=>'2026-01-01T00:00:00Z','end'=>'2026-11-30T23:00:00Z'},'totals'=>m,'employees'=>[],'projects'=>[],'models'=>[],'tools'=>[],'timeseries'=>[]}
    end
    report
    expect(data.dig('comparisons','month','recorded_coverage')).to eq('full_recorded_window')
    expect(data.dig('comparisons','month','state')).to eq('new_activity')
    expect(data.dig('comparisons','month','percent_change')).to be_nil
    expect(data.dig('comparisons','month','previous_tokens')).to eq(0)
  end
  it 'separates posting-time audit filtering from activity dates and paginates' do
    finance_accounts
    Finance::PricedUsagePosting.new.call(finance_payload)
    report('olivia',{audit_start:1.day.ago.utc.iso8601,audit_end:1.day.from_now.utc.iso8601,limit:'1'})
    expect(data['transactions']['total']).to eq(1)
    expect(data['transactions']['rows'].first['expense_delta']).to eq('0.1065')
    expect(data['transactions']['date_basis']).to eq('posting_time')
  end
  it 'returns a retryable failure rather than silently substituting estimates' do
    allow_any_instance_of(Analytics::UsageClient).to receive(:call).and_raise(Analytics::Unavailable)
    report
    expect(response).to have_http_status(:service_unavailable)
    expect(json.dig('error','code')).to eq('usage_analytics_unavailable')
  end
end
