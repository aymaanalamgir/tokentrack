require "rails_helper"

RSpec.describe "Concurrent financial request decisions", type: :model do
  self.use_transactional_tests = false

  before do
    suffix = SecureRandom.hex(6)
    @org = Organization.create!(name: "Request race #{suffix}", slug: "request-race-#{suffix}")
    @finance = User.create!(organization: @org, name: "Finance A", email: "finance-a-#{suffix}@test.example", job_title: "Finance", job_function: "Finance", status: "active")
    @finance_b = User.create!(organization: @org, name: "Finance B", email: "finance-b-#{suffix}@test.example", job_title: "Finance", job_function: "Finance", status: "active")
    @manager = User.create!(organization: @org, name: "Manager", email: "manager-#{suffix}@test.example", job_title: "Manager", job_function: "Engineering", status: "active")
    @employee = User.create!(organization: @org, name: "Employee", email: "employee-#{suffix}@test.example", job_title: "Engineer", job_function: "Engineering", status: "active")
    @unit = OrganizationalUnit.create!(organization: @org, name: "Platform", unit_type: "team")
    OrganizationalMembership.create!(organization: @org, user: @employee, organizational_unit: @unit, membership_type: "home", is_primary: true)
    ReportingRelationship.create!(organization: @org, manager: @manager, report: @employee, relationship_type: "line_manager")
    RoleAssignment.create!(organization: @org, user: @finance, role: "financial_operator", scope_type: "organization")
    RoleAssignment.create!(organization: @org, user: @finance_b, role: "financial_operator", scope_type: "organization")
    RoleAssignment.create!(organization: @org, user: @manager, role: "team_manager", scope_type: "unit", organizational_unit: @unit)
    ApplicationRecord.transaction do
      @project = Project.create!(organization: @org, name: "Race project", slug: "race-project", status: "active")
      ProjectMembership.create!(organization: @org, project: @project, user: @employee, project_role: "owner", joined_at: Time.utc(2026, 11, 1))
      RoleAssignment.create!(organization: @org, user: @employee, role: "project_lead", scope_type: "project", project: @project)
    end
    @accounts = finance_accounts(organization: @org, actor: @finance, initiative: @project, unit: @unit)
    @first = Budgets::AllowanceOperations.new(@finance).revise(user_id: @employee.id, month: "2026-11", amount: "500",
      request_key: "initial-limit", reason: "Concurrency baseline", kind: "ceiling")
    Budgets::AllowanceOperations.new(@finance).delegate(manager_id: @manager.id, unit_id: @unit.id, maximum_amount: "1000",
      from_month: "2026-11", until_month: "2026-11", request_key: "manager-cap", reason: "Concurrency approval authority")
  end

  after do
    raise "Test cleanup only" unless Rails.env.test?
    next unless @org
    ApplicationRecord.transaction do
      guarded = %w[request_events financial_requests spending_limit_allocations spending_limit_revisions spending_limits allowance_delegations ledger_entries financial_transactions priced_usage_receipts]
      guarded.each { |table| ApplicationRecord.connection.execute("ALTER TABLE business.#{table} DISABLE TRIGGER USER") }
      RequestEvent.where(organization: @org).delete_all
      FinancialRequest.where(organization: @org).delete_all
      SpendingLimitAllocation.where(organization: @org).delete_all
      SpendingLimit.where(organization: @org).update_all(current_revision_id: nil)
      SpendingLimitRevision.where(organization: @org).delete_all
      SpendingLimit.where(organization: @org).delete_all
      AllowanceDelegation.where(organization: @org).delete_all
      LedgerEntry.where(organization: @org).delete_all
      FinancialTransaction.where(organization: @org).delete_all
      PricedUsageReceipt.where(organization: @org).delete_all
      BudgetPeriod.where(organization: @org).delete_all
      BudgetAccount.where(organization: @org).delete_all
      ReportingRelationship.where(organization: @org).delete_all
      ProjectMembership.where(organization: @org).delete_all
      RoleAssignment.where(organization: @org).delete_all
      Project.where(organization: @org).delete_all
      OrganizationalMembership.where(organization: @org).delete_all
      OrganizationalUnit.where(organization: @org).delete_all
      User.where(organization: @org).delete_all
      @org.delete
      ApplicationRecord.connection.execute("SET CONSTRAINTS ALL IMMEDIATE")
      guarded.each { |table| ApplicationRecord.connection.execute("ALTER TABLE business.#{table} ENABLE TRIGGER USER") }
    end
  end

  def race
    ready = Queue.new
    start = Queue.new
    results = Queue.new
    threads = 2.times.map do |index|
      Thread.new do
        ApplicationRecord.connection_pool.with_connection do
          ready << true
          start.pop
          begin
            results << yield(index)
          rescue => error
            results << error
          end
        end
      end
    end
    2.times { ready.pop }
    2.times { start << true }
    threads.each(&:join)
    2.times.map { results.pop }
  end

  it "returns one allowance effect for simultaneous identical approval retries" do
    request = Requests::CreateService.new(@employee).call(request_type: "personal_allowance", month: "2026-11",
      requested_amount: "750", reason: "Concurrent allowance", request_key: "allowance-request")
    results = race do
      Requests::DecisionService.new(@manager).approve(id: request.id, operation_key: "same-approval", comment: "Approved")
    end
    expect(results).to all(be_a(FinancialRequest))
    expect(results.map(&:id).uniq).to eq([request.id])
    expect(@first.spending_limit.spending_limit_revisions.count).to eq(2)
    expect(request.request_events.where(event_type: "approved").count).to eq(1)
  end

  it "permits one authoritative funding decision across competing operators" do
    request = Requests::CreateService.new(@employee).call(request_type: "project_funding", month: "2026-11",
      requested_amount: "2", reason: "Concurrent funding", request_key: "funding-request",
      project_id: @project.id, source_account_id: @accounts.fetch("unit").id)
    results = race do |index|
      actor = index.zero? ? @finance : @finance_b
      Requests::DecisionService.new(actor).approve(id: request.id, operation_key: "approval-#{index}", comment: "Approved")
    end
    expect(results.count { |result| result.is_a?(FinancialRequest) }).to eq(1)
    expect(results.count { |result| result.is_a?(Finance::Conflict) }).to eq(1)
    expect(FinancialTransaction.where(organization: @org, source_id: "request/#{request.id}/approve").count).to eq(1)
    expect(request.reload.status).to eq("approved")
    expect(LedgerEntry.where(organization: @org).sum(:funding_delta)).to eq(BigDecimal("100"))
  end
end
