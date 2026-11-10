require "rails_helper"
RSpec.describe "Financial ledger integrity",type: :model do
  it "creates explicitly scoped accounts and UTC monthly periods with no employee account" do
    accounts=finance_accounts
    expect(accounts.keys).to match_array(%w[reserve project unit unassigned])
    expect(accounts.values.flat_map { |a| a.budget_periods.map(&:month_start) }.uniq).to eq([Date.new(2026,11,1)])
    validate_finance_constraints!
  end
  it "preserves all organizational funding while moving allocations" do
    accounts=finance_accounts
    before=LedgerEntry.sum(:funding_delta)
    tx=Finance::Operations.new(person("olivia")).transfer(from:accounts["unit"].id,to:accounts["project"].id,month:"2026-11",amount:"3",key:"transfer-extra",reason:"Cross-functional funding")
    expect(tx.ledger_entries.sum(:funding_delta)).to eq(0)
    expect(tx.ledger_entries.sum(:expense_delta)).to eq(0)
    expect(LedgerEntry.sum(:funding_delta)).to eq(before)
    expect(accounts["unit"].budget_periods.sole.funding).to eq(BigDecimal("17"))
    validate_finance_constraints!
  end
  it "makes manual funding/transfers idempotent and rejects conflicting operation keys" do
    accounts=finance_accounts
    ops=Finance::Operations.new(person("olivia"))
    args={from:accounts["unit"].id,to:accounts["project"].id,month:"2026-11",amount:"3",key:"transfer-repeat",reason:"Test transfer"}
    first=ops.transfer(**args)
    expect(ops.transfer(**args).id).to eq(first.id)
    expect { ops.transfer(**args.merge(amount:"4")) }.to raise_error(Finance::Conflict)
  end
  it "rejects overdrawing transfers and foreign accounts" do
    accounts=finance_accounts
    ops=Finance::Operations.new(person("olivia"))
    expect { ops.transfer(from:accounts["unit"].id,to:accounts["project"].id,month:"2026-11",amount:"21",key:"too-much",reason:"Test") }.to raise_error(Finance::Invalid)
    expect { Finance::Operations.new(person("maya","northstar-labs")).fund(account:accounts["reserve"].id,month:"2026-11",amount:"1",key:"foreign",reason:"Test") }.to raise_error(Finance::Forbidden)
  end
  it "does not infer financial authority from leadership, team management, project leads, or membership labels" do
    %w[olivia marcus priya jordan].each do |key|
      expect { Finance::Operations.new(person(key)).fund(account:SecureRandom.uuid,month:"2026-11",amount:"1",key:"denied",reason:"Test") }.to raise_error(Finance::Forbidden)
    end
  end
  it "uses no floating-point money and retains single-token fractional charges in aggregate" do
    [0.1,"NaN","Infinity","1e-3","0.0000000000000001"].each { |amount| expect { Finance::Money.parse(amount) }.to raise_error(Finance::Invalid) }
    accounts=finance_accounts
    3.times do
      payload=finance_payload.merge("input_cost"=>"0.000000000000001","cached_input_cost"=>"0","output_cost"=>"0","amount"=>"0.000000000000001")
      Finance::PricedUsagePosting.new.call(payload)
    end
    expect(accounts["project"].budget_periods.sole.expenditure).to eq(BigDecimal("0.000000000000003"))
    validate_finance_constraints!
  end
  it "prevents normal and raw SQL mutation of financial history and account ownership" do
    accounts=finance_accounts
    result=Finance::PricedUsagePosting.new.call(finance_payload)
    tx=FinancialTransaction.find(result[:financial_transaction_id]); entry=tx.ledger_entries.sole
    expect { tx.update!(amount:BigDecimal("1")) }.to raise_error(ActiveRecord::ReadOnlyRecord)
    [ -> { FinancialTransaction.where(id:tx.id).update_all(amount:BigDecimal("1")) }, -> { LedgerEntry.where(id:entry.id).delete_all }, -> { BudgetAccount.where(id:accounts["project"].id).update_all(purpose:"unassigned",project_id:nil) } ].each do |operation|
      expect { ApplicationRecord.transaction(requires_new:true) { operation.call } }.to raise_error(ActiveRecord::StatementInvalid)
    end
    validate_finance_constraints!
  end
  it "preserves the original charge while reversing and replacing exactly once" do
    accounts=finance_accounts
    posted=Finance::PricedUsagePosting.new.call(finance_payload)
    original=FinancialTransaction.find(posted[:financial_transaction_id])
    ops=Finance::Operations.new(person("olivia"))
    corrections=ops.correct(original_id:original.id,amount:"0.1",key:"correction",reason:"Synthetic billing adjustment")
    expect(corrections.map(&:kind)).to eq(%w[reversal adjustment])
    expect(original.reload.amount).to eq(BigDecimal("0.1065"))
    expect(accounts["project"].budget_periods.sole.expenditure).to eq(BigDecimal("0.1"))
    expect(ops.correct(original_id:original.id,amount:"0.1",key:"correction",reason:"Synthetic billing adjustment").map(&:id)).to match_array(corrections.map(&:id))
    expect { ops.correct(original_id:original.id,amount:"0.09",key:"second",reason:"Duplicate reversal") }.to raise_error(Finance::Conflict)
    validate_finance_constraints!
  end
  it "supports a standalone expense reversal and disallows changing funding through correction" do
    finance_accounts
    posted=Finance::PricedUsagePosting.new.call(finance_payload)
    reversed=Finance::Operations.new(person("olivia")).correct(original_id:posted[:financial_transaction_id],amount:nil,key:"reverse",reason:"Synthetic reversal")
    expect(reversed.size).to eq(1)
    expect(LedgerEntry.sum(:expense_delta)).to eq(0)
    funding=FinancialTransaction.find_by!(kind:"funding")
    expect { Finance::Operations.new(person("olivia")).correct(original_id:funding.id,amount:nil,key:"bad",reason:"Not an expense") }.to raise_error(ActiveRecord::RecordNotFound)
    validate_finance_constraints!
  end
  it "enforces transfer balance and finite money at the PostgreSQL boundary" do
    accounts=finance_accounts
    period=accounts["project"].budget_periods.sole
    expect do
      ApplicationRecord.transaction(requires_new:true) do
        tx=FinancialTransaction.create!(organization:org,kind:"transfer",currency:"USD",month_start:period.month_start,amount:BigDecimal("1"),source_type:"manual",source_id:"unbalanced",request_fingerprint:"a"*64,actor:person("olivia"),reason:"Invalid direct transfer")
        LedgerEntry.create!(organization:org,financial_transaction:tx,budget_period:period,funding_delta:1,expense_delta:0)
        validate_finance_constraints!
      end
    end.to raise_error(ActiveRecord::StatementInvalid,/equal opposite/)
    expect do
      ApplicationRecord.transaction(requires_new:true) do
        FinancialTransaction.new(organization:org,kind:"funding",currency:"USD",month_start:period.month_start,amount:BigDecimal("NaN"),source_type:"manual",source_id:"nan",request_fingerprint:"a"*64,actor:person("olivia"),reason:"Invalid money").save!(validate:false)
      end
    end.to raise_error(ActiveRecord::StatementInvalid)
  end
  it "keeps an explicitly authorized financial operator inside their own tenant" do
    accounts=finance_accounts
    posted=Finance::PricedUsagePosting.new.call(finance_payload)
    maya=person("maya","northstar-labs")
    RoleAssignment.create!(organization:maya.organization,user:maya,role:"financial_operator",scope_type:"organization")
    foreign=Finance::Operations.new(maya)
    expect { foreign.transfer(from:accounts["unit"].id,to:accounts["project"].id,month:"2026-11",amount:"1",key:"cross",reason:"Cross-tenant denied") }.to raise_error(ActiveRecord::RecordNotFound)
    expect { foreign.correct(original_id:posted[:financial_transaction_id],amount:"0.1",key:"cross-correction",reason:"Cross-tenant denied") }.to raise_error(ActiveRecord::RecordNotFound)
    validate_finance_constraints!
  end

end
