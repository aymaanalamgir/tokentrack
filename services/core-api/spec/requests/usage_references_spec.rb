require "rails_helper"

RSpec.describe "Internal usage reference contract", type: :request do
  let(:credential) { "test-only-reference-credential-000000000000" }
  let(:headers) { { "Authorization" => "Bearer #{credential}" } }
  before { allow(ENV).to receive(:[]).and_call_original; allow(ENV).to receive(:[]).with("USAGE_REFERENCE_TOKEN").and_return(credential) }

  def reference(user = person("jordan"), initiative = project, time: Time.current)
    { key: "reference_1", organization_id: org.id, user_id: user.id, project_id: initiative&.id, occurred_at: time.iso8601(6) }
  end
  def validate_references(entries, auth = headers)
    post "/api/v1/internal/usage-references/validate", params: { references: entries }, headers: auth, as: :json
  end

  it "requires a service credential independently of interactive sessions or browser origin" do
    sign_in("olivia")
    validate_references([reference], origin_headers)
    expect(response).to have_http_status(:unauthorized)
    validate_references([reference], { "Authorization" => "Bearer wrong" })
    expect(response).to have_http_status(:unauthorized)
    validate_references([reference])
    expect(response).to have_http_status(:ok)
    expect(data.first).to eq("key" => "reference_1", "valid" => true)
    expect(response.headers["Cache-Control"]).to include("no-store")
  end

  it "fails closed when the service credential is not configured" do
    allow(ENV).to receive(:[]).with("USAGE_REFERENCE_TOKEN").and_return(nil)
    validate_references([reference])
    expect(response).to have_http_status(:unauthorized)
  end

  it "accepts cross-functional attribution and unassigned activity without changing business records" do
    jordan = person("jordan")
    rows = [reference(jordan, project("fraud-detection")), reference(jordan, project("developer-productivity")).merge(key: "second"), reference(jordan, nil).merge(key: "unassigned")]
    before = [jordan.organizational_memberships.pluck(:id), jordan.manager_relationships.pluck(:id)]
    validate_references(rows)
    expect(data.map { |r| r["valid"] }).to eq([true, true, true])
    expect([jordan.organizational_memberships.pluck(:id), jordan.manager_relationships.pluck(:id)]).to eq(before)
    expect(data.first.keys).to match_array(%w[key valid])
  end

  it "rejects unknown organizations, users, projects, and foreign tenant references" do
    unknown = SecureRandom.uuid
    variants = [[:organization_id, unknown, "UNKNOWN_ORGANIZATION"], [:user_id, unknown, "INVALID_USER_REFERENCE"], [:user_id, person("sam", "northstar-labs").id, "INVALID_USER_REFERENCE"], [:project_id, unknown, "INVALID_PROJECT_REFERENCE"], [:project_id, org("northstar-labs").projects.first.id, "INVALID_PROJECT_REFERENCE"]]
    variants.each do |field, value, code|
      validate_references([reference.merge(field => value)])
      expect(data.first["code"]).to eq(code)
      expect(data.first["valid"]).to be(false)
    end
  end

  it "uses half-open recorded membership periods, including archived projects" do
    membership = ProjectMembership.active.find_by!(project: project, user: person("jordan"))
    joined = membership.joined_at
    membership.update!(left_at: joined + 1.hour)
    project.update!(status: "archived")
    [ [joined - 1.second, false], [joined, true], [joined + 30.minutes, true], [joined + 1.hour, false] ].each do |time, valid|
      validate_references([reference(time: time)])
      expect(data.first["valid"]).to eq(valid)
      expect(data.first["code"]).to eq("PROJECT_MEMBERSHIP_NOT_ESTABLISHED") unless valid
    end
  end

  it "uses known rejoin periods without filling gaps in history" do
    membership = ProjectMembership.active.find_by!(project: project, user: person("jordan"))
    joined = membership.joined_at
    membership.update!(left_at: joined + 1.hour)
    ProjectMembership.create!(organization: org, project: project, user: person("jordan"), joined_at: joined + 3.hours, project_role: "contributor")
    validate_references([reference(time: joined + 2.hours)])
    expect(data.first["valid"]).to be(false)
    validate_references([reference(time: joined + 4.hours)])
    expect(data.first["valid"]).to be(true)
  end

  it "rejects currently inactive users rather than inventing historical eligibility" do
    person("jordan").update!(status: "inactive")
    validate_references([reference(person("jordan"), nil)])
    expect(data.first["code"]).to eq("USER_INELIGIBLE")
  end

  it "bounds batches, validates syntax, and does not accept untyped or duplicate keys" do
    [[], Array.new(101) { reference }, [reference, reference], [reference.merge(user_id: "not-a-uuid")], [reference.merge(project_id: 10)], [reference.merge(occurred_at: "yesterday")], [reference.merge(occurred_at: "2026-11-09T12:00:00")]].each do |entries|
      validate_references(entries)
      expect(response).to have_http_status(:bad_request)
    end
  end

  it "returns a safe infrastructure error when business reference queries fail" do
    allow(UsageReferenceValidation).to receive(:new).and_raise(ActiveRecord::ConnectionNotEstablished)
    validate_references([reference])
    expect(response).to have_http_status(:service_unavailable)
    expect(json).to eq("error" => { "code" => "reference_data_unavailable", "message" => "Organizational references are temporarily unavailable" })
  end

  it "exports minimal flagged fictional snapshot identifiers and recorded periods" do
    get "/api/v1/internal/usage-references/demo-snapshot", headers: headers
    expect(response).to have_http_status(:ok)
    expect(data["organizations"].size).to eq(2)
    expect(data["users"].size).to eq(74)
    expect(data["users"].first.keys).to match_array(%w[id organization_id job_function primary_unit_id])
    expect(data["memberships"].first.keys).to match_array(%w[organization_id user_id project_id joined_at left_at])
    expect(data.to_json).not_to include("email", "managers", "permissions")
    allow(DemoSession).to receive(:enabled?).and_return(false)
    get "/api/v1/internal/usage-references/demo-snapshot", headers: headers
    expect(response).to have_http_status(:not_found)
  end
end
