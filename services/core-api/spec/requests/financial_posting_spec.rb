require "rails_helper"
RSpec.describe "Priced usage financial consumer", type: :request do
  let(:token) { "financial-test-credential-only-000000000000" }
  let(:headers) { { "Authorization"=>"Bearer #{token}" } }
  before do
    allow(ENV).to receive(:[]).and_call_original
    allow(ENV).to receive(:[]).with("USAGE_FINANCIAL_TOKEN").and_return(token)
  end
  def deliver(payload,auth=headers)
    post "/api/v1/internal/priced-usage-events",params:payload,headers:auth,as: :json
  end
  it "requires the dedicated service credential, never a demo session or read credential" do
    sign_in("olivia")
    deliver(finance_payload,origin_headers)
    expect(response).to have_http_status(:unauthorized)
    deliver(finance_payload,{"Authorization"=>"Bearer reference-only-credential-00000000000"})
    expect(response).to have_http_status(:unauthorized)
  end
  it "posts the exact cached-token example once to its project, retaining employee/home dimensions" do
    accounts=finance_accounts
    payload=finance_payload
    deliver(payload)
    expect(response).to have_http_status(:created)
    tx=FinancialTransaction.find(json["financial_transaction_id"])
    expect(tx.amount).to eq(BigDecimal("0.1065"))
    expect(tx.ledger_entries.sole.budget_period.budget_account_id).to eq(accounts["project"].id)
    expect(tx.home_unit_id).to eq(team("platform").id)
    expect(tx.user_id).to eq(person("jordan").id)
    expect(tx.project_id).to eq(project.id)
    validate_finance_constraints!
    expect { deliver(payload) }.not_to change(LedgerEntry,:count)
    expect(response).to have_http_status(:ok)
    expect(json["duplicate"]).to be(true)
    expect(json["amount"]).to eq("0.1065")
  end
  it "rejects a changed payload and a second priced identity for the same canonical event" do
    finance_accounts
    payload=finance_payload
    deliver(payload)
    expect { deliver(payload.merge("amount"=>"0.2065","input_cost"=>"0.16")) }.not_to change(FinancialTransaction,:count)
    expect(response).to have_http_status(:conflict)
    deliver(payload.merge("priced_event_id"=>SecureRandom.uuid))
    expect(response).to have_http_status(:conflict)
  end
  it "normalizes equivalent decimal/time spellings before comparing replay fingerprints" do
    finance_accounts
    payload=finance_payload
    deliver(payload)
    deliver(payload.merge("amount"=>"0.106500000000000","occurred_at"=>"2026-11-15T16:30:00+02:00"))
    expect(response).to have_http_status(:ok)
    expect(json["duplicate"]).to be(true)
  end
  it "holds unresolved ownership durably and posts on a later retry after explicit funding" do
    accounts=finance_accounts(funded:false)
    payload=finance_payload
    deliver(payload)
    expect(response).to have_http_status(:accepted)
    expect(json["status"]).to eq("unresolved")
    expect(PricedUsageReceipt.find(payload["priced_event_id"]).resolution_code).to eq("NO_FUNDED_CHARGE_OWNER")
    ops=Finance::Operations.new(person("olivia"))
    ops.fund(account:accounts["reserve"].id,month:"2026-11",amount:"10",key:"later-funding",reason:"Resolve held usage")
    ops.transfer(from:accounts["reserve"].id,to:accounts["project"].id,month:"2026-11",amount:"1",key:"later-allocation",reason:"Resolve held usage")
    deliver(payload)
    expect(response).to have_http_status(:created)
    validate_finance_constraints!
  end
  it "uses home-team funding then explicit unassigned funding without inventing historical home membership" do
    accounts=finance_accounts
    accounts["project"].update!(status:"inactive")
    payload=finance_payload
    deliver(payload)
    tx=FinancialTransaction.find(json["financial_transaction_id"])
    expect(tx.ledger_entries.sole.budget_period.budget_account_id).to eq(accounts["unit"].id)
    OrganizationalMembership.where(user:person("jordan"),is_primary:true).update_all(updated_at:Time.utc(2026,11,16))
    deliver(finance_payload)
    tx=FinancialTransaction.find(json["financial_transaction_id"])
    expect(tx.home_unit_id).to be_nil
    expect(tx.ledger_entries.sole.budget_period.budget_account_id).to eq(accounts["unassigned"].id)
    validate_finance_constraints!
  end
  it "preserves valid historical project expense for an inactive user and archived project" do
    finance_accounts
    person("jordan").update!(status:"inactive")
    project.update!(status:"archived")
    deliver(finance_payload)
    expect(response).to have_http_status(:created)
    validate_finance_constraints!
  end
  it "holds a project with no event-time membership rather than guessing historical authority" do
    finance_accounts
    payload=finance_payload.merge("occurred_at"=>"2026-11-01T00:00:00.000000Z")
    deliver(payload)
    expect(response).to have_http_status(:accepted)
    expect(json["code"]).to eq("PROJECT_HISTORY_UNRESOLVED")
  end
  it "records genuine expense even when the available allocation becomes negative" do
    accounts=finance_accounts
    payload=finance_payload.merge("amount"=>"40.1065","input_cost"=>"40.06")
    deliver(payload)
    expect(response).to have_http_status(:created)
    expect(accounts["project"].budget_periods.sole.available).to eq(BigDecimal("-20.1065"))
    validate_finance_constraints!
  end
  it "rejects monetary floats, invalid precision/components/profiles, versions, and raw extra fields" do
    finance_accounts
    [ {"amount"=>0.1065},{"amount"=>"NaN"},{"amount"=>"0.0000000000000001"},{"amount"=>"1"},{"schema_version"=>2},{"billing_basis"=>"cache_write"},{"prompt"=>"private content"} ].each do |change|
      deliver(finance_payload.merge(change))
      expect(response).to have_http_status(:unprocessable_content)
    end
    expect(PricedUsageReceipt.count).to eq(0)
  end
  it "rejects foreign users/projects without cross-tenant financial writes" do
    finance_accounts
    deliver(finance_payload.merge("user_id"=>person("sam","northstar-labs").id))
    expect(response).to have_http_status(:unprocessable_content)
    deliver(finance_payload.merge("project_id"=>org("northstar-labs").projects.first.id))
    expect(response).to have_http_status(:unprocessable_content)
    expect(PricedUsageReceipt.count).to eq(0)
  end
  it "exposes narrow reconciliation with original and net amounts after correction" do
    finance_accounts
    payload=finance_payload
    deliver(payload)
    id=json["financial_transaction_id"]
    Finance::Operations.new(person("olivia")).correct(original_id:id,amount:"0.1",key:"correct-1",reason:"Synthetic correction")
    validate_finance_constraints!
    post "/api/v1/internal/financial-reconciliation",params:{priced_event_ids:[payload["priced_event_id"]]},headers:headers,as: :json
    expect(response).to have_http_status(:ok)
    expect(data.sole).to include("original_amount"=>"0.1065","net_amount"=>"0.1","adjustment_delta"=>"-0.0065","status"=>"posted")
    expect(json["integrity"].values).to all(eq(0))
  end
end
