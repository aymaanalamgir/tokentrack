require "rails_helper"
RSpec.describe "Concurrent financial operations",type: :model do
  self.use_transactional_tests = false
  before do
    @organization=Organization.create!(name:"Isolated financial concurrency",slug:"finance-test-#{SecureRandom.hex(8)}")
    @actor=User.create!(organization:@organization,name:"Financial test actor",email:"finance@test.example",job_title:"Test",job_function:"Test",status:"active",demo_identity:false)
    @unit=OrganizationalUnit.create!(organization:@organization,name:"Test team",unit_type:"team")
    @accounts=finance_accounts(organization:@organization,actor:@actor,initiative:nil,unit:@unit)
  end
  after do
    # Ordinary specs roll back. These committed-thread tests clean only their
    # isolated tenant in the test DB, using transactional DDL as schema owner.
    # There is no runtime bypass of ledger immutability in application code.
    raise "Test cleanup only" unless Rails.env.test?
    next unless @organization
    ApplicationRecord.transaction do
      %w[ledger_entries financial_transactions priced_usage_receipts].each { |table| ApplicationRecord.connection.execute("ALTER TABLE business.#{table} DISABLE TRIGGER USER") }
      LedgerEntry.where(organization:@organization).delete_all
      PricedUsageReceipt.where(organization:@organization).update_all(status:"unresolved",financial_transaction_id:nil)
      FinancialTransaction.where(organization:@organization).delete_all
      PricedUsageReceipt.where(organization:@organization).delete_all
      BudgetPeriod.where(organization:@organization).delete_all
      BudgetAccount.where(organization:@organization).delete_all
      RoleAssignment.where(organization:@organization).delete_all
      OrganizationalUnit.where(organization:@organization).delete_all
      User.where(organization:@organization).delete_all
      @organization.delete
      %w[ledger_entries financial_transactions priced_usage_receipts].each { |table| ApplicationRecord.connection.execute("ALTER TABLE business.#{table} ENABLE TRIGGER USER") }
    end
  end
  def race
    ready=Queue.new; start=Queue.new; results=Queue.new
    threads=2.times.map do |index|
      Thread.new do
        ApplicationRecord.connection_pool.with_connection do
          ready << true; start.pop
          begin results << yield(index)
          rescue => error; results << error
          end
        end
      end
    end
    2.times { ready.pop };2.times { start << true };threads.each(&:join)
    2.times.map { results.pop }
  end
  it "posts one authoritative expense despite simultaneous matching deliveries" do
    payload=finance_payload(organization:@organization,user:@actor,initiative:nil)
    results=race { Finance::PricedUsagePosting.new.call(payload) }
    expect(results).to all(be_a(Hash))
    expect(results.map { |r| r[:duplicate] }).to contain_exactly(false,true)
    expect(FinancialTransaction.where(organization:@organization,kind:"usage_charge").count).to eq(1)
    expect(LedgerEntry.where(organization:@organization).sum(:expense_delta)).to eq(BigDecimal("0.1065"))
  end
  it "serializes competing transfers without overdrawing or creating funding" do
    results=race do |index|
      Finance::Operations.new(@actor).transfer(from:@accounts["unassigned"].id,to:@accounts["unit"].id,month:"2026-11",amount:"15",key:"competing-#{index}",reason:"Concurrent test transfer")
    end
    expect(results.count { |r| r.is_a?(FinancialTransaction) }).to eq(1)
    expect(results.count { |r| r.is_a?(Finance::Invalid) }).to eq(1)
    expect(@accounts["unassigned"].budget_periods.sole.available).to eq(BigDecimal("5"))
    expect(LedgerEntry.where(organization:@organization).sum(:funding_delta)).to eq(BigDecimal("100"))
  end
  it "permits only one reversal and replacement under concurrent corrections" do
    payload=finance_payload(organization:@organization,user:@actor,initiative:nil)
    posted=Finance::PricedUsagePosting.new.call(payload)
    results=race { |index| Finance::Operations.new(@actor).correct(original_id:posted[:financial_transaction_id],amount:"0.1",key:"correction-#{index}",reason:"Concurrent correction") }
    expect(results.count { |r| r.is_a?(Array) }).to eq(1)
    expect(results.count { |r| r.is_a?(Finance::Conflict) }).to eq(1)
    expect(FinancialTransaction.where(organization:@organization,kind:"reversal").count).to eq(1)
    expect(LedgerEntry.where(organization:@organization).sum(:expense_delta)).to eq(BigDecimal("0.1"))
  end
end
