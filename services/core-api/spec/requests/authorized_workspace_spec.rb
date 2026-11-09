require "rails_helper"

RSpec.describe "Authorized organizational workspace", type: :request do
  it "returns distinct database-backed overview experiences for all four personas" do
    { "olivia" => "leadership", "marcus" => "manager", "priya" => "project_lead", "jordan" => "employee" }.each do |key, persona|
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
    sign_in("olivia")
    get "/api/v1/organizational-units/#{team('platform').id}"
    expect(response).to have_http_status(:ok)
    expect(data["roster_visibility"]).to eq("management")
    get "/api/v1/users/#{person('casey').id}"
    expect(data["email"]).to eq(person("casey").email)
    expect(data).not_to have_key("role_assignments")
  end

  it "lets managers inspect direct reports and denies unrelated management profiles" do
    sign_in("marcus")
    get "/api/v1/users/#{person('jordan').id}?view=management"
    expect(response).to have_http_status(:ok)
    expect(data["email"]).to eq(person("jordan").email)
    get "/api/v1/users/#{person('casey').id}?view=management"
    expect(response).to have_http_status(:forbidden)
    expect(response.body).not_to include(person("casey").email)
  end

  it "shows project contributors as directory records, not private profiles" do
    sign_in("priya")
    get "/api/v1/projects/#{project.id}"
    expect(response).to have_http_status(:ok)
    expect(data["can_edit"]).to be(true)
    expect(data["teams"].size).to be > 1
    expect(data["members"]).to all(include("visibility" => "directory"))
    expect(data["members"].any? { |m| m.key?("email") || m.key?("managers") }).to be(false)
    get "/api/v1/users/#{person('jordan').id}/reporting-context"
    expect(response).to have_http_status(:forbidden)
  end

  it "gives employees self details and limits coworker directory projection" do
    sign_in("jordan")
    get "/api/v1/users/#{person('jordan').id}"
    expect(data["email"]).to eq(person("jordan").email)
    expect(data["memberships"].count).to eq(2)
    get "/api/v1/users/#{person('marcus').id}"
    expect(response).to have_http_status(:ok)
    expect(data["visibility"]).to eq("directory")
    expect(data).not_to have_key("email")
    expect(data).not_to have_key("managers")
    get "/api/v1/users/#{person('marcus').id}?view=management"
    expect(response).to have_http_status(:forbidden)
  end

  it "scopes organization explorer rosters rather than returning the enterprise directory" do
    hidden = User.create!(organization: org, name: "Unrelated Person", email: "hidden@aperture.example", job_title: "Analyst", job_function: "Finance")
    OrganizationalMembership.create!(organization: org, user: hidden, organizational_unit: team("finance"), is_primary: true)
    sign_in("jordan")
    get "/api/v1/users"
    expect(data.map { |u| u["id"] }).not_to include(hidden.id)
    expect(data.select { |u| u["id"] != person("jordan").id }.any? { |u| u.key?("email") }).to be(false)
    get "/api/v1/organizational-units/#{team('finance').id}"
    expect(data["members"].map { |u| u["id"] }).not_to include(hidden.id) if response.status == 200
  end

  it "denies cross-tenant object lookups and does not broaden scope through parameters" do
    sign_in("olivia")
    other = org("northstar-labs")
    ["organizations/#{other.id}", "users/#{other.users.first.id}", "organizational-units/#{other.organizational_units.first.id}", "projects/#{other.projects.first.id}"].each do |path|
      get "/api/v1/#{path}"
      expect(response).to have_http_status(:not_found)
    end
    get "/api/v1/users", params: { organization_id: other.id, user_id: other.users.first.id }
    expect(data.map { |u| u["id"] } & other.users.pluck(:id)).to eq([])
  end

  it "returns reporting ancestry and direct reports only for an authorized context" do
    sign_in("jordan")
    get "/api/v1/users/#{person('jordan').id}/reporting-context"
    expect(response).to have_http_status(:ok)
    expect(data["ancestors"].map { |u| u["name"] }).to include("Marcus Rivera", "Ellis Morgan", "Olivia Chen")
    get "/api/v1/me/access"
    expect(data["capabilities"]).not_to include("requests.approve.team", "budgets.manage.team")
    expect(data["grants"]).to all(include("scope_type" => "self"))
  end

  it "permits scoped project metadata editing and rejects unrelated grants or memberships" do
    sign_in("priya")
    patch "/api/v1/projects/#{project.id}", params: { project: { name: "Fraud Detection Updated", organization_id: org("northstar-labs").id } }, headers: origin_headers, as: :json
    expect(response).to have_http_status(:ok)
    expect(project.reload.name).to eq("Fraud Detection Updated")
    expect(project.organization_id).to eq(org.id)
    patch "/api/v1/projects/#{project('developer-productivity').id}", params: { project: { name: "Unauthorized" } }, headers: origin_headers, as: :json
    expect(response).to have_http_status(:not_found)
    sign_in("jordan")
    patch "/api/v1/projects/#{project.id}", params: { project: { name: "Unauthorized" } }, headers: origin_headers, as: :json
    expect(response).to have_http_status(:forbidden)
  end

  it "rejects invalid project updates with structured errors" do
    sign_in("priya")
    patch "/api/v1/projects/#{project.id}", params: { project: { name: "", status: "invalid" } }, headers: origin_headers, as: :json
    expect(response).to have_http_status(:unprocessable_content)
    expect(json["error"]["code"]).to eq("invalid_record")
  end

  it "filters authorized projects by status, department, and membership and paginates results" do
    sign_in("jordan")
    get "/api/v1/projects", params: { membership: "mine", status: "active", department: team("platform").id, limit: 1 }
    expect(response).to have_http_status(:ok)
    expect(data.size).to eq(1)
    expect(data.first["status"]).to eq("active")
    expect(json["meta"]["limit"]).to eq(1)
    get "/api/v1/projects", params: { membership: "led" }
    expect(data).to eq([])
  end

  it "bounds project participant responses and retains the total contributor count" do
    sign_in("priya")
    get "/api/v1/projects/#{project.id}", params: { limit: 1 }
    expect(data["members"].size).to eq(1)
    expect(data["members_meta"]["total"]).to eq(project.project_memberships.count)
    expect(data["contributor_count"]).to eq(project.project_memberships.count)
  end
end
