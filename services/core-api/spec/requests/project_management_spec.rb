require "rails_helper"

RSpec.describe "Project management", type: :request do
  def create_project(name = "Cross Functional Demo", lead: nil)
    sign_in("priya")
    post "/api/v1/projects", params: { project: { name: name, description: "Shared initiative", status: "planned", initial_lead_id: lead } }, headers: origin_headers, as: :json
    expect(response).to have_http_status(:created)
    Project.find(data["id"])
  end

  def add_member(record, user, role = "contributor")
    post "/api/v1/projects/#{record.id}/memberships", params: { membership: { user_id: user.id, project_role: role } }, headers: origin_headers, as: :json
  end

  def status(record, value)
    patch "/api/v1/projects/#{record.id}", params: { project: { status: value } }, headers: origin_headers, as: :json
  end

  it "creates a tenant-bound project with explicit administration and author attribution" do
    record = create_project
    expect(record.organization).to eq(org)
    expect(record.created_by).to eq(person("priya"))
    expect(record.slug).to eq("cross-functional-demo")
    expect(record.active_project_memberships.find_by!(user: person("priya")).project_role).to eq("owner")
    expect(RoleAssignment.find_by!(user: person("priya"), project: record).role).to eq("project_lead")
  end

  it "permits an explicitly chosen initial lead, retaining the creator as a reviewer" do
    record = create_project(lead: person("jordan").id)
    expect(RoleAssignment.where(project: record, role: "project_lead").pluck(:user_id)).to eq([person("jordan").id])
    expect(record.active_project_memberships.find_by!(user: person("priya")).project_role).to eq("reviewer")
    expect(data["can_edit"]).to be(false)
  end

  it "does not infer creation or mutation rights from leadership or managerial read grants" do
    RoleAssignment.where(user: person("olivia"), role: "project_creator").delete_all
    %w[olivia marcus jordan].each do |key|
      sign_in(key)
      post "/api/v1/projects", params: { project: { name: "Denied" } }, headers: origin_headers, as: :json
      expect(response).to have_http_status(:forbidden)
    end
    sign_in("marcus")
    add_member(project, person("sofia"))
    expect(response).to have_http_status(:forbidden)
  end

  it "rejects invalid/duplicate slugs and foreign initial leads without partial projects" do
    record = create_project
    expect {
      post "/api/v1/projects", params: { project: { name: record.name } }, headers: origin_headers, as: :json
      expect(response).to have_http_status(:unprocessable_content)
    }.not_to change(Project, :count)
    post "/api/v1/projects", params: { project: { name: "Foreign", initial_lead_id: person("sam", "northstar-labs").id } }, headers: origin_headers, as: :json
    expect(response).to have_http_status(:not_found)
  end

  it "finds eligible active colleagues with minimal directory metadata and bounded results" do
    record = create_project
    get "/api/v1/projects/#{record.id}/eligible-users", params: { q: "Jordan", limit: 1 }
    expect(data.size).to eq(1)
    expect(data.first["name"]).to eq("Jordan Lee")
    expect(data.first).not_to have_key("email")
    expect(data.first).not_to have_key("managers")
    expect(data.first["organization_id"]).to be_nil
    sign_in("jordan")
    get "/api/v1/projects/eligible-users"
    expect(response).to have_http_status(:forbidden)
  end

  it "adds cross-functional contributors without changing their home team or reporting manager" do
    record = create_project
    jordan = person("jordan")
    before = [jordan.organizational_memberships.pluck(:id), jordan.manager_relationships.pluck(:id)]
    add_member(record, jordan)
    expect(response).to have_http_status(:created)
    add_member(record, person("sofia"), "lead")
    expect(response).to have_http_status(:created)
    expect(RoleAssignment.where(user: person("sofia"), project: record)).to be_empty
    get "/api/v1/projects/#{record.id}/team-groups"
    expect(data.map { |g| g["unit"]["name"] }).to include("Platform Engineering", "Product Design", "Product Management")
    expect([jordan.organizational_memberships.pluck(:id), jordan.manager_relationships.pluck(:id)]).to eq(before)
    sign_in("jordan")
    get "/api/v1/users/#{jordan.id}"
    expect(data["projects"].map { |p| p["id"] }).to include(record.id)
    add_member(record, person("casey"))
    expect(response).to have_http_status(:forbidden)
  end

  it "rejects duplicate active memberships, invalid roles, and cross-tenant assignments" do
    record = create_project
    add_member(record, person("jordan"))
    add_member(record, person("jordan"))
    expect(response).to have_http_status(:unprocessable_content)
    add_member(record, person("sofia"), "administrator")
    expect(response).to have_http_status(:unprocessable_content)
    add_member(record, person("sam", "northstar-labs"))
    expect(response).to have_http_status(:not_found)
  end

  it "edits collaboration roles without granting authority" do
    record = create_project
    add_member(record, person("jordan"))
    id = data["id"]
    patch "/api/v1/projects/#{record.id}/memberships/#{id}", params: { membership: { project_role: "owner", user_id: person("olivia").id } }, headers: origin_headers, as: :json
    expect(response).to have_http_status(:ok)
    expect(ProjectMembership.find(id).user).to eq(person("jordan"))
    expect(AccessPolicy.new(person("jordan")).edit_project?(record)).to be(false)
  end

  it "ends periods, hides removed assignments, and permits rejoining without destroying history" do
    record = create_project
    add_member(record, person("jordan"))
    old_id = data["id"]
    delete "/api/v1/projects/#{record.id}/memberships/#{old_id}", params: {}, headers: origin_headers, as: :json
    expect(response).to have_http_status(:ok)
    expect(ProjectMembership.find(old_id).left_at).to be_present
    sign_in("jordan")
    get "/api/v1/projects/#{record.id}"
    expect(response).to have_http_status(:not_found)
    sign_in("priya")
    add_member(record, person("jordan"))
    expect(response).to have_http_status(:created)
    expect(data["id"]).not_to eq(old_id)
    get "/api/v1/projects/#{record.id}/memberships", params: { state: "past" }
    expect(data.map { |m| m["id"] }).to include(old_id)
    expect(record.project_memberships.where(user: person("jordan")).count).to eq(2)
  end

  it "prevents last-admin removal, revokes removed grants, and transfers atomically" do
    record = create_project
    owner = record.active_project_memberships.find_by!(user: person("priya"))
    delete "/api/v1/projects/#{record.id}/memberships/#{owner.id}", params: {}, headers: origin_headers, as: :json
    expect(response).to have_http_status(:unprocessable_content)
    post "/api/v1/projects/#{record.id}/transfer-ownership", params: { user_id: person("jordan").id }, headers: origin_headers, as: :json
    expect(response).to have_http_status(:ok)
    expect(data["can_edit"]).to be(false)
    expect(RoleAssignment.where(project: record, role: "project_lead").pluck(:user_id)).to eq([person("jordan").id])
    expect(owner.reload.project_role).to eq("contributor")
    status(record, "active")
    expect(response).to have_http_status(:forbidden)
    sign_in("jordan")
    status(record, "active")
    expect(response).to have_http_status(:ok)
    expect(AccessPolicy.new(person("jordan")).management_profile?(person("priya"))).to be(false)
  end

  it "does not partially transfer to a foreign or inactive person" do
    record = create_project
    post "/api/v1/projects/#{record.id}/transfer-ownership", params: { user_id: person("sam", "northstar-labs").id }, headers: origin_headers, as: :json
    expect(response).to have_http_status(:not_found)
    expect(RoleAssignment.where(project: record, role: "project_lead").pluck(:user_id)).to eq([person("priya").id])
    person("sofia").update!(status: "inactive")
    post "/api/v1/projects/#{record.id}/transfer-ownership", params: { user_id: person("sofia").id }, headers: origin_headers, as: :json
    expect(response).to have_http_status(:not_found)
    expect(RoleAssignment.where(project: record, role: "project_lead").pluck(:user_id)).to eq([person("priya").id])
  end

  it "revokes an exiting administrator's grant when another administrator remains" do
    record = create_project
    ProjectManagement.new(person("priya")).add_member(record, person("jordan").id, "lead")
    RoleAssignment.create!(organization: org, user: person("jordan"), project: record, role: "project_lead", scope_type: "project")
    owner = record.active_project_memberships.find_by!(user: person("priya"))
    delete "/api/v1/projects/#{record.id}/memberships/#{owner.id}", params: {}, headers: origin_headers, as: :json
    expect(response).to have_http_status(:ok)
    expect(RoleAssignment.where(project: record, user: person("priya"))).to be_empty
    expect(record.active_project_memberships.where(user: person("priya"))).to be_empty
    patch "/api/v1/projects/#{record.id}", params: { project: { name: "Revoked" } }, headers: origin_headers, as: :json
    expect(response).to have_http_status(:not_found)
  end

  it "rejects unauthenticated creation and unsafe mutation origins" do
    post "/api/v1/projects", params: { project: { name: "Denied" } }, headers: origin_headers, as: :json
    expect(response).to have_http_status(:unauthorized)
    sign_in("priya")
    post "/api/v1/projects", params: { project: { name: "Denied" } }, headers: { "Origin" => "https://unrelated.example" }, as: :json
    expect(response).to have_http_status(:forbidden)
  end

  it "archives and restores stable projects with memberships intact and read-only archived data" do
    record = create_project
    add_member(record, person("jordan"))
    ids = record.project_memberships.pluck(:id)
    status(record, "active")
    status(record, "archived")
    expect(response).to have_http_status(:ok)
    expect(record.reload.archived_from_status).to eq("active")
    expect(data["permissions"]["members_manage"]).to be(false)
    add_member(record, person("sofia"))
    expect(response).to have_http_status(:forbidden)
    patch "/api/v1/projects/#{record.id}", params: { project: { name: "No edits" } }, headers: origin_headers, as: :json
    expect(response).to have_http_status(:forbidden)
    status(record, "active")
    expect(response).to have_http_status(:ok)
    expect(record.project_memberships.pluck(:id)).to match_array(ids)
    expect(record.reload.status).to eq("active")
  end

  it "restricts history and tenant IDs even when the requester knows a membership UUID" do
    record = create_project
    add_member(record, person("jordan"))
    id = data["id"]
    sign_in("jordan")
    get "/api/v1/projects/#{record.id}/memberships", params: { state: "all" }
    expect(response).to have_http_status(:forbidden)
    delete "/api/v1/projects/#{record.id}/memberships/#{id}", params: {}, headers: origin_headers, as: :json
    expect(response).to have_http_status(:forbidden)
    foreign = org("northstar-labs").projects.first
    get "/api/v1/projects/#{foreign.id}/memberships"
    expect(response).to have_http_status(:not_found)
  end

  it "enforces the last-admin invariant in PostgreSQL for direct grant deletion" do
    record = create_project
    expect {
      ApplicationRecord.transaction(requires_new: true) do
        RoleAssignment.where(project: record, role: "project_lead").delete_all
        ApplicationRecord.connection.execute("SET CONSTRAINTS ALL IMMEDIATE")
      end
    }.to raise_error(ActiveRecord::StatementInvalid, /administrator/)
    expect(RoleAssignment.where(project: record, role: "project_lead").count).to eq(1)
  end

  it "enforces membership foreign keys and active uniqueness without model validations" do
    record = create_project
    add_member(record, person("jordan"))
    expect {
      ApplicationRecord.transaction(requires_new: true) do
        ProjectMembership.new(organization: org, project: record, user: person("jordan"), project_role: "contributor", joined_at: Time.current).save!(validate: false)
      end
    }.to raise_error(ActiveRecord::RecordNotUnique)
    expect {
      ApplicationRecord.transaction(requires_new: true) do
        ProjectMembership.new(organization: org, project: record, user: person("sam", "northstar-labs"), project_role: "contributor", joined_at: Time.current).save!(validate: false)
      end
    }.to raise_error(ActiveRecord::InvalidForeignKey)
  end
end
