module FinanceHelpers
  def finance_payload(organization: org, user: person("jordan"), initiative: project, id: SecureRandom.uuid, usage_id: SecureRandom.uuid, amount: "0.1065")
    { "schema_version"=>1,"calculation_version"=>1,"priced_event_id"=>id,"usage_event_id"=>usage_id,"organization_id"=>organization.id,"user_id"=>user.id,"project_id"=>initiative&.id,
      "source"=>"financial-spec","source_event_id"=>"event-1","usage_fingerprint"=>"a"*64,"provider"=>"openai","model"=>"gpt-5.4-mini","tool"=>"coding-assistant","agent_run_id"=>nil,"workflow_type"=>nil,
      "pricing_provider"=>"openai","pricing_model"=>"gpt-5.4-mini","pricing_rate_id"=>SecureRandom.uuid,"pricing_mapping_id"=>SecureRandom.uuid,"pricing_tier"=>"standard_text_cache_read","billing_basis"=>"synthetic_standard_cache_read","currency"=>"USD",
      "input_tokens"=>100000,"cached_input_tokens"=>20000,"output_tokens"=>10000,"input_rate"=>"0.75","cached_input_rate"=>"0.075","output_rate"=>"4.5",
      "input_cost"=>"0.06","cached_input_cost"=>"0.0015","output_cost"=>"0.045","amount"=>amount,"occurred_at"=>"2026-11-15T14:30:00.000000Z",
      "rate_effective_from"=>"2026-11-01T00:00:00.000000Z","rate_effective_until"=>nil,"rate_source_url"=>"https://developers.openai.com/api/docs/pricing","rate_verified_at"=>"2026-11-09T00:00:00.000000Z" }
  end
  def finance_accounts(organization: org, actor: person("olivia"), initiative: project, unit: team("platform"), funded: true)
    RoleAssignment.find_or_create_by!(organization: organization,user: actor,role: "financial_operator",scope_type: "organization")
    owners={"reserve"=>nil,"unassigned"=>nil}
    owners["project"]=initiative if initiative
    owners["unit"]=unit if unit
    accounts=owners.to_h do |purpose,owner|
      a=BudgetAccount.create!(organization: organization,name: "#{purpose} test budget",purpose: purpose,currency: "USD",effective_from: Time.utc(2026,11,1),project_id: purpose=="project" ? owner.id : nil,organizational_unit_id: purpose=="unit" ? owner.id : nil)
      BudgetPeriod.create!(organization: organization,budget_account: a,month_start: Date.new(2026,11,1),currency: "USD",status: "open")
      [purpose,a]
    end
    if funded
      ops=Finance::Operations.new(actor)
      ops.fund(account: accounts.fetch("reserve").id,month:"2026-11",amount:"100",key:"fund-test",reason:"Test funding")
      accounts.except("reserve").each { |purpose,a| ops.transfer(from: accounts.fetch("reserve").id,to:a.id,month:"2026-11",amount:"20",key:"allocate-#{purpose}",reason:"Test allocation") }
    end
    accounts
  end
  def validate_finance_constraints!
    ApplicationRecord.connection.execute("SET CONSTRAINTS ALL IMMEDIATE")
    ApplicationRecord.connection.execute("SET CONSTRAINTS ALL DEFERRED")
  end
end
RSpec.configure { |config| config.include FinanceHelpers }
