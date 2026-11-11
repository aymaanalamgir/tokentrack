require "rails_helper"

RSpec.describe "Financial request and approval API", type: :request do
  let(:month) { "2026-11" }
  let(:olivia) { person("olivia") }
  let(:jordan) { person("jordan") }
  let(:marcus) { person("marcus") }
  let(:priya) { person("priya") }

  def establish_ceiling(user = jordan, amount: "500", key: SecureRandom.uuid)
    Budgets::AllowanceOperations.new(olivia).revise(user_id: user.id, month: month, amount: amount,
      request_key: key, reason: "Request workflow baseline", kind: "ceiling")
  end

  def delegate(cap: "1000", key: SecureRandom.uuid)
    Budgets::AllowanceOperations.new(olivia).delegate(manager_id: marcus.id, unit_id: team("platform").id,
      maximum_amount: cap, from_month: month, until_month: month, request_key: key, reason: "Request approval authority")
  end

  def create_personal(amount: "750", key: SecureRandom.uuid)
    Requests::CreateService.new(jordan).call(request_type: "personal_allowance", month: month,
      requested_amount: amount, reason: "Additional development work", request_key: key)
  end

  def create_project(accounts, amount: "2", key: SecureRandom.uuid)
    Requests::CreateService.new(priya).call(request_type: "project_funding", month: month,
      requested_amount: amount, reason: "More evaluation activity", request_key: key,
      project_id: project.id, source_account_id: accounts.fetch("unit").id)
  end

  before { allow_any_instance_of(Analytics::UsageClient).to receive(:call).and_raise(Analytics::Unavailable) }

  it "routes a delegated personal request and approves exactly one immutable revision without ledger movement" do
    finance_accounts
    first = establish_ceiling
    delegate
    request = create_personal
    expect(request.assigned_approver).to eq(marcus)
    expect(request.routing_reason).to include("1000 USD")
    ledger_count = FinancialTransaction.count
    approved = Requests::DecisionService.new(marcus).approve(id: request.id, operation_key: "approve-personal", comment: "Within delegated authority")
    expect(approved.reload).to have_attributes(status: "approved", execution_transaction_id: nil)
    expect(approved.execution_revision.limit_amount).to eq(BigDecimal("750"))
    expect(approved.execution_revision.revision_number).to eq(first.revision_number + 1)
    expect(FinancialTransaction.count).to eq(ledger_count)
    expect(approved.request_events.pluck(:event_type)).to eq(%w[created submitted approved executed])
  end

  it "routes above-cap allowance requests to financial authority and prevents self approval" do
    finance_accounts
    establish_ceiling
    delegate
    request = create_personal(amount: "1500")
    expect(request.assigned_approver).to eq(olivia)
    expect(request.routing_reason).to include("Financial operator")
    expect { Requests::DecisionService.new(jordan).approve(id: request.id, operation_key: "self", comment: "No") }.to raise_error(Finance::Forbidden)
    expect(request.reload.status).to eq("pending")
  end

  it "revalidates revoked manager authority and stale allowance revisions" do
    finance_accounts
    first = establish_ceiling
    grant = delegate
    revoked = create_personal
    Budgets::AllowanceOperations.new(olivia).revoke(grant.id)
    expect { Requests::DecisionService.new(marcus).approve(id: revoked.id, operation_key: "revoked", comment: "Old authority") }.to raise_error(Finance::Forbidden)
    expect(revoked.reload.status).to eq("pending")

    fresh = create_personal(amount: "800")
    Budgets::AllowanceOperations.new(olivia).revise(user_id: jordan.id, month: month, amount: "600",
      expected_revision: first.id, request_key: "intervening", reason: "Current change", kind: "ceiling")
    expect { Requests::DecisionService.new(olivia).approve(id: fresh.id, operation_key: "stale", comment: "Outdated") }.to raise_error(Finance::Conflict, /changed after submission/)
    expect(fresh.reload.status).to eq("pending")
  end

  it "executes project funding once through the balanced ledger and conserves organization funding" do
    accounts = finance_accounts
    request = create_project(accounts)
    total = LedgerEntry.where(organization: org).sum(:funding_delta)
    approved = Requests::DecisionService.new(olivia).approve(id: request.id, operation_key: "project-approve", comment: "Approved evaluation")
    replay = Requests::DecisionService.new(olivia).approve(id: request.id, operation_key: "project-approve", comment: "Approved evaluation")
    expect(replay.id).to eq(approved.id)
    expect(FinancialTransaction.where(source_type: "funding_transfer", source_id: "request/#{request.id}/approve").count).to eq(1)
    expect(LedgerEntry.where(organization: org).sum(:funding_delta)).to eq(total)
    expect(approved.reload.execution_transaction.ledger_entries.count).to eq(2)
  end

  it "allows a manager to request team funding but requires a different financial operator" do
    accounts = finance_accounts
    request = Requests::CreateService.new(marcus).call(request_type: "team_funding", month: month,
      requested_amount: "3", reason: "Increased development demand", request_key: "team-request",
      unit_id: team("platform").id, source_account_id: accounts.fetch("reserve").id)
    expect(request.assigned_approver).to eq(olivia)
    expect { Requests::DecisionService.new(marcus).approve(id: request.id, operation_key: "team-self", comment: "No") }.to raise_error(Finance::Forbidden)
    expect { Requests::DecisionService.new(olivia).approve(id: request.id, operation_key: "team-ok", comment: "Approved") }.to change { FinancialTransaction.where(source_id: "request/#{request.id}/approve").count }.by(1)
  end

  it "records rejection and cancellation without financial effects" do
    accounts = finance_accounts
    rejected = create_project(accounts)
    before = FinancialTransaction.count
    Requests::DecisionService.new(olivia).reject(id: rejected.id, operation_key: "reject", comment: "Not justified")
    own = create_project(accounts, key: "cancel-me")
    Requests::DecisionService.new(priya).cancel(id: own.id, operation_key: "cancel", comment: "No longer needed")
    expect(rejected.reload.status).to eq("rejected")
    expect(own.reload.status).to eq("cancelled")
    expect(FinancialTransaction.count).to eq(before)
  end

  it "rolls back approval when source funding becomes insufficient" do
    accounts = finance_accounts
    request = create_project(accounts, amount: "15")
    Finance::Operations.new(olivia).transfer(from: accounts.fetch("unit").id, to: accounts.fetch("reserve").id,
      month: month, amount: "10", key: "drain-source", reason: "Capacity changed")
    expect { Requests::DecisionService.new(olivia).approve(id: request.id, operation_key: "insufficient", comment: "Attempt") }.to raise_error(Finance::Invalid, /exceeds/)
    expect(request.reload).to have_attributes(status: "pending", execution_transaction_id: nil, resolved_at: nil)
    expect(request.request_events.where(event_type: "approved")).to be_empty
  end

  it "keeps request payloads and events immutable at Ruby and database layers" do
    finance_accounts
    establish_ceiling
    request = create_personal
    event = request.request_events.first
    expect { request.update!(requested_amount: 900) }.to raise_error(ActiveRecord::StatementInvalid)
    expect { event.update!(reason: "Changed") }.to raise_error(ActiveRecord::ReadOnlyRecord)
    expect { ApplicationRecord.transaction(requires_new: true) { event.update_columns(reason: "Changed") } }.to raise_error(ActiveRecord::StatementInvalid)
  end

  it "rejects an approved state without its type-correct business execution reference" do
    finance_accounts
    establish_ceiling
    request = create_personal
    expect do
      ApplicationRecord.transaction(requires_new: true) do
        request.update_columns(status: "approved", resolved_at: Time.current)
      end
    end.to raise_error(ActiveRecord::StatementInvalid)
    expect(request.reload).to have_attributes(status: "pending", execution_revision_id: nil, execution_transaction_id: nil)
  end

  it "exposes only own, assigned, or financially authorized request data through the API" do
    finance_accounts
    establish_ceiling
    delegate
    request = create_personal
    sign_in("jordan")
    get "/api/v1/requests", params: { month: month }
    expect(data["my_requests"].map { |row| row["id"] }).to include(request.id)
    expect(data["pending_review"]).to be_empty
    sign_in("marcus")
    get "/api/v1/requests", params: { month: month }
    expect(data["pending_review"].map { |row| row["id"] }).to include(request.id)
    sign_in("sofia")
    get "/api/v1/requests/#{request.id}"
    expect(response).to have_http_status(:not_found)
    post "/api/v1/requests/#{request.id}/approve", params: { request_action: { operation_key: "private", comment: "No authority" } }, headers: origin_headers, as: :json
    expect(response).to have_http_status(:not_found)
  end

  it "validates API origins, tenant references, filters, and stable creation keys" do
    accounts = finance_accounts
    sign_in("priya")
    body = { request_type: "project_funding", month: month, requested_amount: "2", reason: "API request",
      request_key: "api-create", project_id: project.id, source_account_id: accounts.fetch("unit").id }
    post "/api/v1/requests", params: { request: body }, headers: origin_headers, as: :json
    expect(response).to have_http_status(:created)
    id = data["id"]
    post "/api/v1/requests", params: { request: body }, headers: origin_headers, as: :json
    expect(data["id"]).to eq(id)
    post "/api/v1/requests", params: { request: body.merge(requested_amount: "3") }, headers: origin_headers, as: :json
    expect(response).to have_http_status(:conflict)
    get "/api/v1/requests", params: { requester_id: person("maya", "northstar-labs").id }
    expect(data["my_requests"]).to be_empty
    post "/api/v1/requests/#{id}/cancel", params: { request_action: { operation_key: "bad-origin", comment: "No" } }, headers: { "Origin" => "https://foreign.example" }, as: :json
    expect(response).to have_http_status(:forbidden)
  end
end
