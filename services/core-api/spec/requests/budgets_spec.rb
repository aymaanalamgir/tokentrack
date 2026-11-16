require 'rails_helper'
RSpec.describe 'Budget and spending-control API',type: :request do
  let(:month){'2026-11'}
  def ops(actor=person('financial_operator')) = Budgets::AllowanceOperations.new(actor)
  def ceiling(user=person('employee'),amount:'500',expected:nil,key:SecureRandom.uuid)
    ops.revise(user_id:user.id,month:month,amount:amount,expected_revision:expected,request_key:key,reason:'Explicit test ceiling',kind:'ceiling')
  end
  def allocate(root,amount:'250',actor:person('employee'),expected:root.current_revision_id,project_id:project.id,key:SecureRandom.uuid)
    ops(actor).revise(user_id:actor.id,month:month,allocations:[{project_id:project_id,amount:amount}],expected_revision:expected,request_key:key,reason:'Test unused-capacity partition',kind:'reallocation')
  end
  def budget_post(path,body)
    post "/api/v1/budgets/#{path}",params:{budget:body},headers:origin_headers,as: :json
  end
  before do
    allow_any_instance_of(Analytics::UsageClient).to receive(:call).and_raise(Analytics::Unavailable)
  end
  it 'establishes a monthly ceiling and revisions without creating ledger money' do
    finance_accounts
    before=LedgerEntry.where(organization:org).sum(:funding_delta);expenses=FinancialTransaction.count
    first=ceiling;root=first.spending_limit
    revision=allocate(root)
    expect(root.reload.current_revision_id).to eq(revision.id)
    expect(root.spending_limit_revisions.count).to eq(2)
    expect(revision.limit_amount).to eq(BigDecimal('500'))
    expect(revision.spending_limit_allocations.sole.limit_amount).to eq(BigDecimal('250'))
    expect(LedgerEntry.where(organization:org).sum(:funding_delta)).to eq(before)
    expect(FinancialTransaction.count).to eq(expenses)
    validate_finance_constraints!
  end
  it 'enforces one ceiling per tenant employee month and separates new months' do
    finance_accounts;first=ceiling
    duplicate=first.spending_limit.dup
    expect{ApplicationRecord.transaction(requires_new:true){duplicate.save!(validate:false)}}.to raise_error(ActiveRecord::RecordNotUnique)
    second=ops.revise(user_id:person('employee').id,month:'2026-12',amount:'100',request_key:'new-month',reason:'Explicit next-month control without funding',kind:'ceiling')
    expect(second.spending_limit.month_start).to eq(Date.new(2026,12,1))
    expect(LedgerEntry.where(organization:org).sum(:funding_delta)).to eq(BigDecimal('100'))
  end
  it 'handles corrections using only the individual employee expense' do
    finance_accounts
    first=ceiling
    posted=Finance::PricedUsagePosting.new.call(finance_payload)
    Finance::Operations.new(person('financial_operator')).correct(original_id:posted[:financial_transaction_id],amount:'0.1',key:'budget-correction',reason:'Correct employee expense')
    sign_in('employee');get '/api/v1/budgets',params:{month:month}
    expect(response).to have_http_status(:ok)
    expect(data['own_allowance']).to include('consumption'=>'0.1','remaining'=>'499.9')
    expect(data['coverage']['status']).to eq('unavailable')
    expect(data['accounts']).to eq([])
  end
  it 'rejects allocations above the ceiling, duplicates, negative amounts and foreign projects atomically' do
    finance_accounts;root=ceiling.spending_limit
    [ [{project_id:project.id,amount:'501'}], [{project_id:project.id,amount:'1'},{project_id:project.id,amount:'1'}], [{project_id:project.id,amount:'-1'}] ].each do |rows|
      expect{ops(person('employee')).revise(user_id:person('employee').id,month:month,allocations:rows,expected_revision:root.current_revision_id,request_key:SecureRandom.uuid,reason:'Invalid partition',kind:'reallocation')}.to raise_error(Finance::Invalid)
    end
    foreign=Project.find_by!(organization:org('memento-ai'))
    expect{allocate(root,project_id:foreign.id)}.to raise_error(ActiveRecord::RecordNotFound)
    expect(root.reload.spending_limit_revisions.count).to eq(1)
  end
  it 'requires current eligible participation for new increases and preserves past allocation history' do
    finance_accounts;root=ceiling.spending_limit
    original=allocate(root,amount:'10')
    ProjectMembership.active.where(user:person('employee'),project:project).update_all(left_at:Time.current)
    expect{allocate(root.reload,amount:'11')}.to raise_error(Finance::Invalid)
    reduced=allocate(root.reload,amount:'5')
    expect(reduced.spending_limit_allocations.sole.limit_amount).to eq(BigDecimal('5'))
    expect(original.spending_limit_allocations.sole.limit_amount).to eq(BigDecimal('10'))
  end
  it 'permits redistribution only from unused capacity including the unassigned portion' do
    finance_accounts;root=ceiling(amount:'1').spending_limit
    Finance::PricedUsagePosting.new.call(finance_payload)
    allocate(root,amount:'0.5')
    expect{allocate(root.reload,amount:'0.01')}.to raise_error(Finance::Invalid,/unused/)
    Finance::PricedUsagePosting.new.call(finance_payload(initiative:nil,id:SecureRandom.uuid,usage_id:SecureRandom.uuid))
    expect{allocate(root.reload,amount:'0.99')}.to raise_error(Finance::Invalid,/Unassigned/)
  end
  it 'returns idempotent revisions before stale checks and rejects conflicting or stale updates' do
    finance_accounts;first=ceiling;root=first.spending_limit;key=SecureRandom.uuid
    second=allocate(root,key:key)
    expect(allocate(root.reload,expected:first.id,key:key).id).to eq(second.id)
    expect{allocate(root,amount:'200',expected:first.id,key:key)}.to raise_error(Finance::Conflict)
    expect{allocate(root,amount:'200',expected:first.id)}.to raise_error(Finance::Conflict)
  end
  it 'does not grant a manager ceiling authority without a capped delegation' do
    finance_accounts
    expect{ops(person('manager')).revise(user_id:person('employee').id,month:month,amount:'500',request_key:'no-delegation',reason:'Test',kind:'ceiling')}.to raise_error(Finance::Forbidden)
    grant=ops.delegate(manager_id:person('manager').id,unit_id:team('payments-core').id,maximum_amount:'500',from_month:month,until_month:month,request_key:'explicit-cap',reason:'Explicit direct report scope')
    first=ops(person('manager')).revise(user_id:person('employee').id,month:month,amount:'500',request_key:'delegated',reason:'Test',kind:'ceiling')
    expect(first.limit_amount).to eq(BigDecimal('500'))
    expect{ops(person('manager')).revise(user_id:person('employee').id,month:month,amount:'501',expected_revision:first.id,request_key:'too-large',reason:'Test',kind:'ceiling')}.to raise_error(Finance::Forbidden)
    expect{ops(person('manager')).revise(user_id:person('colleague').id,month:month,amount:'100',request_key:'unrelated',reason:'Test',kind:'ceiling')}.to raise_error(Finance::Forbidden)
    ops.revoke(grant.id)
    expect{ops(person('manager')).revise(user_id:person('employee').id,month:month,amount:'400',expected_revision:first.id,request_key:'revoked',reason:'Test',kind:'ceiling')}.to raise_error(Finance::Forbidden)
  end
  it 'does not let an employee increase their ceiling, edit a coworker or transfer money' do
    finance_accounts;ceiling
    sign_in('employee')
    budget_post('ceilings',{user_id:person('employee').id,month:month,amount:'999',expected_revision:SpendingLimit.where(organization:org).sole.current_revision_id,request_key:'self-raise',reason:'No authority'})
    expect(response).to have_http_status(:forbidden)
    get '/api/v1/budgets',params:{month:month,user_id:person('colleague').id};expect(response).to have_http_status(:not_found)
    budget_post('transfers',{from_account_id:BudgetAccount.find_by!(organization:org,purpose:'reserve').id,to_account_id:BudgetAccount.find_by!(organization:org,purpose:'project').id,month:month,amount:'1',request_key:'forbidden-transfer',reason:'No financial grant'})
    expect(response).to have_http_status(:forbidden)
  end
  it 'protects project leads from unrelated personal allowance disclosure and permits scoped contributor cost' do
    finance_accounts;ceiling
    Finance::PricedUsagePosting.new.call(finance_payload)
    RoleAssignment.find_or_create_by!(organization:org,user:person('project_lead'),role:'project_budget_reader',scope_type:'project',project:project)
    sign_in('project_lead');get '/api/v1/budgets',params:{month:month,project_id:project.id}
    expect(response).to have_http_status(:ok)
    expect(data['project_contributors'].find{|r|r['user_id']==person('employee').id}['net_expenditure']).to eq('0.1065')
    expect(data['employees'].map{|r|r['user_id']}).to eq([person('project_lead').id])
    get '/api/v1/budgets',params:{month:month,user_id:person('employee').id};expect(response).to have_http_status(:not_found)
  end
  it 'allows explicit organization budget read without granting financial mutations' do
    finance_accounts
    RoleAssignment.where(user:person('financial_operator'),role:'financial_operator').delete_all
    RoleAssignment.create!(organization:org,user:person('financial_operator'),role:'organization_budget_reader',scope_type:'organization')
    sign_in('financial_operator');get '/api/v1/budgets',params:{month:month}
    expect(data['summary']['funding']).to eq('100')
    expect(data['capabilities']['transfer']).to be(false)
    budget_post('funding',{account_id:BudgetAccount.find_by!(organization:org,purpose:'reserve').id,month:month,amount:'1',request_key:'reader',reason:'Not authorized'})
    expect(response).to have_http_status(:forbidden)
  end
  it 'conserves funding through the existing idempotent transfer API and refuses closed periods' do
    accounts=finance_accounts;sign_in('financial_operator')
    body={from_account_id:accounts['unit'].id,to_account_id:accounts['project'].id,month:month,amount:'3',request_key:'api-transfer',reason:'Explicit test transfer'}
    budget_post('transfers',body);expect(response).to have_http_status(:ok);id=data['id']
    budget_post('transfers',body);expect(data['id']).to eq(id)
    expect(LedgerEntry.where(organization:org).sum(:funding_delta)).to eq(BigDecimal('100'))
    expect(LedgerEntry.where(organization:org).sum(:expense_delta)).to eq(0)
    accounts['unit'].budget_periods.sole.update!(status:'closed')
    budget_post('transfers',body.merge(request_key:'closed'))
    expect(response).to have_http_status(:unprocessable_content)
  end
  it 'records explicit reserve funding once through the existing fund operation' do
    accounts=finance_accounts;sign_in('financial_operator')
    body={account_id:accounts['reserve'].id,month:month,amount:'50',request_key:'explicit-fund-api',reason:'Explicit organization funding, never an allowance allocation'}
    budget_post('funding',body);expect(response).to have_http_status(:ok);id=data['id']
    budget_post('funding',body);expect(data['id']).to eq(id)
    expect(LedgerEntry.where(organization:org).sum(:funding_delta)).to eq(BigDecimal('150'))
    expect(LedgerEntry.where(organization:org).sum(:expense_delta)).to eq(0)
  end
  it 'opens empty monthly periods without rollover or funding' do
    finance_accounts;sign_in('financial_operator')
    before=LedgerEntry.count
    budget_post('periods',{month:'2026-12'});expect(response).to have_http_status(:ok)
    budget_post('periods',{month:'2026-12'});expect(data['funding_created']).to eq('0')
    expect(BudgetPeriod.where(month_start:Date.new(2026,12,1)).count).to eq(4)
    expect(LedgerEntry.count).to eq(before)
  end
  it 'paginates funding history independently from the employee table' do
    finance_accounts;sign_in('financial_operator')
    get '/api/v1/budgets',params:{month:month,limit:'1',offset:'1',history_offset:'0'}
    expect(response).to have_http_status(:ok)
    expect(data['employees_meta']['offset']).to eq(1)
    expect(data['history']['offset']).to eq(0)
    expect(data['history']['rows'].size).to eq(1)
    get '/api/v1/budgets',params:{month:month,limit:'1',offset:'0',history_offset:'1'}
    expect(data['employees_meta']['offset']).to eq(0)
    expect(data['history']['offset']).to eq(1)
  end
  it 'preserves revision and allocation immutability even for direct SQL writes' do
    finance_accounts;root=ceiling.spending_limit;revision=allocate(root)
    expect{revision.update!(limit_amount:1000)}.to raise_error(ActiveRecord::ReadOnlyRecord)
    expect{ApplicationRecord.transaction(requires_new:true){revision.update_columns(limit_amount:1000)}}.to raise_error(ActiveRecord::StatementInvalid)
    allocation=revision.spending_limit_allocations.sole
    expect{ApplicationRecord.transaction(requires_new:true){allocation.update_columns(limit_amount:'1')}}.to raise_error(ActiveRecord::StatementInvalid)
    validate_finance_constraints!
  end
  it 'rejects a raw SQL partition sum above the ceiling at commit' do
    finance_accounts
    expect do
      ApplicationRecord.transaction(requires_new:true) do
        root=SpendingLimit.create!(organization:org,user:person('employee'),month_start:Date.new(2026,11,1),currency:'USD')
        revision=SpendingLimitRevision.create!(organization:org,spending_limit:root,revision_number:1,limit_amount:'1',set_by:person('financial_operator'),kind:'ceiling',request_key:'raw',request_fingerprint:'a'*64,reason:'Test')
        SpendingLimitAllocation.create!(organization:org,spending_limit_revision:revision,project:project,limit_amount:'2')
        root.update!(current_revision:revision)
        validate_finance_constraints!
      end
    end.to raise_error(ActiveRecord::StatementInvalid)
  end
  it 'denies foreign tenants, wrong origin and invalid monetary/month inputs' do
    finance_accounts;sign_in('financial_operator')
    budget_post('ceilings',{user_id:person('leadership','memento-ai').id,month:month,amount:'1',expected_revision:nil,request_key:'foreign',reason:'Test'});expect(response).to have_http_status(:not_found)
    ['2026-13','not-a-month','2100-01'].each{|m|get '/api/v1/budgets',params:{month:m};expect(response).to have_http_status(:unprocessable_content)}
    post '/api/v1/budgets/allocations',params:{budget:{}},headers:{'Origin'=>'https://foreign.example'},as: :json;expect(response).to have_http_status(:forbidden)
  end
end
