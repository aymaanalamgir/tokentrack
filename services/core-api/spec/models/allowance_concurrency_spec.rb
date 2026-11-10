require 'rails_helper'
RSpec.describe 'Concurrent spending controls',type: :model do
  self.use_transactional_tests=false
  before do
    @org=Organization.create!(name:'Isolated allowance concurrency',slug:"allowance-race-#{SecureRandom.hex(8)}")
    @actor=User.create!(organization:@org,name:'Control actor',email:'controls@test.example',job_title:'Test',job_function:'Test',status:'active')
    @unit=OrganizationalUnit.create!(organization:@org,name:'Control team',unit_type:'team')
    @accounts=finance_accounts(organization:@org,actor:@actor,initiative:nil,unit:@unit)
    ApplicationRecord.transaction do
      @project=Project.create!(organization:@org,name:'Control project',slug:'control-project',status:'active')
      ProjectMembership.create!(organization:@org,project:@project,user:@actor,project_role:'owner',joined_at:Time.utc(2026,11,1))
      RoleAssignment.create!(organization:@org,user:@actor,role:'project_lead',scope_type:'project',project:@project)
    end
    @first=Budgets::AllowanceOperations.new(@actor).revise(user_id:@actor.id,month:'2026-11',amount:'500',request_key:'initial',reason:'Initial concurrency control',kind:'ceiling')
  end
  after do
    raise 'Test cleanup only' unless Rails.env.test?
    next unless @org
    ApplicationRecord.transaction do
      tables=%w[spending_limits spending_limit_revisions spending_limit_allocations allowance_delegations ledger_entries financial_transactions priced_usage_receipts]
      tables.each{|t|ApplicationRecord.connection.execute("ALTER TABLE business.#{t} DISABLE TRIGGER USER")}
      SpendingLimitAllocation.where(organization:@org).delete_all
      SpendingLimit.where(organization:@org).update_all(current_revision_id:nil)
      SpendingLimitRevision.where(organization:@org).delete_all
      SpendingLimit.where(organization:@org).delete_all
      AllowanceDelegation.where(organization:@org).delete_all
      LedgerEntry.where(organization:@org).delete_all
      FinancialTransaction.where(organization:@org).delete_all
      PricedUsageReceipt.where(organization:@org).delete_all
      BudgetPeriod.where(organization:@org).delete_all
      BudgetAccount.where(organization:@org).delete_all
      ProjectMembership.where(organization:@org).delete_all
      RoleAssignment.where(organization:@org).delete_all
      Project.where(organization:@org).delete_all
      OrganizationalUnit.where(organization:@org).delete_all
      User.where(organization:@org).delete_all
      @org.delete
      ApplicationRecord.connection.execute("SET CONSTRAINTS ALL IMMEDIATE")
      tables.each{|t|ApplicationRecord.connection.execute("ALTER TABLE business.#{t} ENABLE TRIGGER USER")}
    end
  end
  def race
    ready=Queue.new;start=Queue.new;results=Queue.new
    threads=2.times.map{|i|Thread.new{ApplicationRecord.connection_pool.with_connection{ready<<true;start.pop;begin results<<yield(i);rescue=>e;results<<e;end}}}
    2.times{ready.pop};2.times{start<<true};threads.each(&:join);2.times.map{results.pop}
  end
  it 'rejects adding allocations to a revision from an earlier committed transaction' do
    expect{SpendingLimitAllocation.create!(organization:@org,spending_limit_revision:@first,project:@project,limit_amount:'1')}.to raise_error(ActiveRecord::StatementInvalid)
  end
  it 'serializes reallocations and rejects the stale competing revision' do
    results=race do |i|
      Budgets::AllowanceOperations.new(@actor).revise(user_id:@actor.id,month:'2026-11',allocations:[{project_id:@project.id,amount:(300+i*100).to_s}],expected_revision:@first.id,request_key:"race-#{i}",reason:'Concurrent allocation',kind:'reallocation')
    end
    expect(results.count{|r|r.is_a?(SpendingLimitRevision)}).to eq(1)
    expect(results.count{|r|r.is_a?(Finance::Conflict)}).to eq(1)
    expect(@first.spending_limit.spending_limit_revisions.count).to eq(2)
    expect(LedgerEntry.where(organization:@org).sum(:funding_delta)).to eq(BigDecimal('100'))
  end
  it 'serializes concurrent ceiling revisions without lost updates' do
    results=race{|i|Budgets::AllowanceOperations.new(@actor).revise(user_id:@actor.id,month:'2026-11',amount:(600+i*100).to_s,expected_revision:@first.id,request_key:"ceiling-#{i}",reason:'Concurrent ceiling',kind:'ceiling')}
    expect(results.count{|r|r.is_a?(SpendingLimitRevision)}).to eq(1)
    expect(results.count{|r|r.is_a?(Finance::Conflict)}).to eq(1)
  end
  it 'returns the same revision for simultaneous identical requests' do
    results=race{|_|Budgets::AllowanceOperations.new(@actor).revise(user_id:@actor.id,month:'2026-11',amount:'600',expected_revision:@first.id,request_key:'same-operation',reason:'Same request',kind:'ceiling')}
    expect(results).to all(be_a(SpendingLimitRevision))
    expect(results.map(&:id).uniq.size).to eq(1)
    expect(@first.spending_limit.spending_limit_revisions.count).to eq(2)
  end
end
