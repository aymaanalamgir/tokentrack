namespace :requests do
  desc "Create idempotent local Slice 8 request scenarios without resetting financial history"
  task demo_setup: :environment do
    abort "Local demo only" unless DemoSession.enabled?
    org = Organization.find_by!(slug: "aperture-technologies")
    users = %w[olivia marcus priya jordan sofia].to_h { |key| [key, User.find_by!(organization: org, email: "#{key}@aperture-technologies.example")] }
    month = "2026-11"
    platform = OrganizationalUnit.find(DemoData.uuid("aperture-technologies/unit/platform"))
    fraud = Project.find_by!(organization: org, slug: "fraud-detection")
    reserve = BudgetAccount.find_by!(organization: org, purpose: "reserve", currency: "USD")
    platform_account = BudgetAccount.find_by!(organization: org, purpose: "unit", organizational_unit_id: platform.id, currency: "USD")
    abort "Run finance:demo_setup and budgets:demo_setup first" unless reserve && platform_account && SpendingLimit.exists?(organization: org, user: users["jordan"], month_start: Date.new(2026, 11, 1))

    create = lambda do |actor, attributes|
      Requests::CreateService.new(actor).call(**attributes)
    end
    scenarios = []
    scenarios << create.call(users["jordan"], request_type: "personal_allowance", month: month, requested_amount: "750",
      reason: "Additional development work", request_key: "slice8-jordan-750-v1")
    scenarios << create.call(users["jordan"], request_type: "personal_allowance", month: month, requested_amount: "1500",
      reason: "Expanded cross-project development work", request_key: "slice8-jordan-1500-v1")
    scenarios << create.call(users["priya"], request_type: "project_funding", month: month, requested_amount: "2000",
      reason: "Increased model evaluation activity", request_key: "slice8-fraud-2000-reserve-v2", project_id: fraud.id, source_account_id: reserve.id)
    scenarios << create.call(users["marcus"], request_type: "team_funding", month: month, requested_amount: "3000",
      reason: "Increased Platform Engineering development demand", request_key: "slice8-platform-3000-v1", unit_id: platform.id, source_account_id: reserve.id)
    rejected = create.call(users["sofia"], request_type: "personal_allowance", month: month, requested_amount: "0.1",
      reason: "Additional design exploration", request_key: "slice8-sofia-rejection-v1")
    if rejected.pending?
      Requests::DecisionService.new(users["olivia"]).reject(id: rejected.id, operation_key: "slice8-sofia-rejection-decision-v1", comment: "Use the existing project allocation this month")
    end
    scenarios << rejected.reload
    puts JSON.pretty_generate(scenarios: scenarios.map { |request| { id: request.id, type: request.request_type, status: request.status,
      requester: request.requester.name, assigned_approver: request.assigned_approver&.name, routing_reason: request.routing_reason } })
  end
end
