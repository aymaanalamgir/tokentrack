require "rails_helper"

RSpec.describe "Authorized organizational workspace", type: :request do
  it "returns distinct database-backed overview experiences for all four personas" do
    { "leadership" => "leadership", "manager" => "manager", "project_lead" => "project_lead", "employee" => "employee" }.each do |key, persona|
      sign_in(key)
      get "/api/v1/me/overview"
      expect(response).to have_http_status(:ok)
      expect(data["persona"]).to eq(persona)
      expect(data["counts"]).to all(include("value" => a_kind_of(Integer)))
      expect(data).not_to have_key("spending")
      expect(data["counts"].first["value"]).to eq(org.users.count) if persona == "leadership"
    end
  end

  it "lets leadership explore units, rosters, and employee details in its tenant" do
    sign_in("leadership")
    get "/api/v1/organizational-units/#{team('payments-core').id}"
    expect(response).to have_http_status(:ok)
    expect(data["roster_visibility"]).to eq("management")
    get "/api/v1/users/#{person('financial_operator').id}"
    expect(data["email"]).to eq(person("financial_operator").email)
    expect(data).not_to have_key("role_assignments")
  end

  it "lets managers inspect direct reports and denies unrelated management profiles" do
    sign_in("manager")
    get "/api/v1/users/#{person('employee').id}?view=management"
    expect(response).to have_http_status(:ok)
    expect(data["email"]).to eq(person("employee").email)
    get "/api/v1/users/#{person('director').id}?view=management"
    expect(response).to have_http_status(:forbidden)
    expect(response.body).not_to include(person("director").email)
  end

  it "shows project contributors as directory records, not private profiles" do
    sign_in("project_lead")
    get "/api/v1/projects/#{project.id}"
    expect(response).to have_http_status(:ok)
    expect(data["can_edit"]).to be(true)
    expect(data["teams"].size).to be > 1
    expect(data["members"]).to all(include("visibility" => "directory"))
    expect(data["members"].any? { |m| m.key?("email") || m.key?("managers") }).to be(false)
    get "/api/v1/users/#{person('employee').id}/reporting-context"
    expect(response).to have_http_status(:forbidden)
  end

  it "gives employees self details and limits coworker directory projection" do
    sign_in("employee")
    get "/api/v1/users/#{person('employee').id}"
    expect(data["email"]).to eq(person("employee").email)
    expect(data["memberships"].count).to eq(2)
    get "/api/v1/users/#{person('manager').id}"
    expect(response).to have_http_status(:ok)
    expect(data["visibility"]).to eq("directory")
    expect(data).not_to have_key("email")
    expect(data).not_to have_key("managers")
    get "/api/v1/users/#{person('manager').id}?view=management"
    expect(response).to have_http_status(:forbidden)
  end

  it "scopes organization explorer rosters rather than returning the enterprise directory" do
    hidden = User.create!(organization: org, name: "Unrelated Person", email: "hidden@northline-financial.example", job_title: "Analyst", job_function: "Finance")
    OrganizationalMembership.create!(organization: org, user: hidden, organizational_unit: team("finance"), is_primary: true)
    sign_in("employee")
    get "/api/v1/users"
    expect(data.map { |u| u["id"] }).not_to include(hidden.id)
    expect(data.select { |u| u["id"] != person("employee").id }.any? { |u| u.key?("email") }).to be(false)
    get "/api/v1/organizational-units/#{team('finance').id}"
    expect(data["members"].map { |u| u["id"] }).not_to include(hidden.id) if response.status == 200
  end

  it "denies cross-tenant object lookups and does not broaden scope through parameters" do
    sign_in("leadership")
    other = org("memento-ai")
    ["organizations/#{other.id}", "users/#{other.users.first.id}", "organizational-units/#{other.organizational_units.first.id}", "projects/#{other.projects.first.id}"].each do |path|
      get "/api/v1/#{path}"
      expect(response).to have_http_status(:not_found)
    end
    get "/api/v1/users", params: { organization_id: other.id, user_id: other.users.first.id }
    expect(data.map { |u| u["id"] } & other.users.pluck(:id)).to eq([])
  end

  it "returns reporting ancestry and direct reports only for an authorized context" do
    sign_in("employee")
    get "/api/v1/users/#{person('employee').id}/reporting-context"
    expect(response).to have_http_status(:ok)
    expect(data["ancestors"].map { |u| u["name"] }).to include("Elliot Brandt", "Tobias Wren", "Amara Lindqvist")
    get "/api/v1/me/access"
    expect(data["capabilities"]).not_to include("requests.approve.team", "budgets.manage.team")
    expect(data["grants"]).to all(include("scope_type" => "self"))
  end

  it "permits scoped project metadata editing and rejects unrelated grants or memberships" do
    sign_in("project_lead")
    patch "/api/v1/projects/#{project.id}", params: { project: { name: "Fraud Detection Updated", organization_id: org("memento-ai").id } }, headers: origin_headers, as: :json
    expect(response).to have_http_status(:ok)
    expect(project.reload.name).to eq("Fraud Detection Updated")
    expect(project.organization_id).to eq(org.id)
    patch "/api/v1/projects/#{project('real-time-payments').id}", params: { project: { name: "Unauthorized" } }, headers: origin_headers, as: :json
    expect(response).to have_http_status(:not_found)
    sign_in("employee")
    patch "/api/v1/projects/#{project.id}", params: { project: { name: "Unauthorized" } }, headers: origin_headers, as: :json
    expect(response).to have_http_status(:forbidden)
  end

  it "rejects invalid project updates with structured errors" do
    sign_in("project_lead")
    patch "/api/v1/projects/#{project.id}", params: { project: { name: "", status: "invalid" } }, headers: origin_headers, as: :json
    expect(response).to have_http_status(:unprocessable_content)
    expect(json["error"]["code"]).to eq("invalid_record")
  end

  it "filters authorized projects by status, department, and membership and paginates results" do
    sign_in("employee")
    get "/api/v1/projects", params: { membership: "mine", status: "active", department: team("payments-core").id, limit: 1 }
    expect(response).to have_http_status(:ok)
    expect(data.size).to eq(1)
    expect(data.first["status"]).to eq("active")
    expect(json["meta"]["limit"]).to eq(1)
    get "/api/v1/projects", params: { membership: "led" }
    expect(data).to eq([])
  end

  it "bounds project participant responses and retains the total contributor count" do
    sign_in("project_lead")
    get "/api/v1/projects/#{project.id}", params: { limit: 1 }
    expect(data["members"].size).to eq(1)
    expect(data["members_meta"]["total"]).to eq(project.active_project_memberships.count)
    expect(data["contributor_count"]).to eq(project.active_project_memberships.count)
  end
end
