# Specs run against the seeded fictional companies (rails_helper seeds DEMO_COMPANIES). Northline Financial is
# the primary tenant; Memento AI is the foreign tenant for isolation checks.
#
# People are addressed by their persona in demo/enterprise/companies-v1.json, so a scenario reads as a role:
#   leadership          Amara Lindqvist, CEO: organization viewer and project creator
#   financial_operator  Gabriel Moreau, CFO: financial operator and organization viewer
#   director            Tobias Wren, VP Engineering: manages the Payments Core and Ledger Services teams
#   manager             Elliot Brandt, Payments Core lead: team manager and lead of Real-Time Payments
#   project_lead        Mateo Alvarez: leads Fraud Detection Engine and may start projects; no reports
#   employee            Hana Takeda, Payments Core engineer reporting to Elliot; Data Engineering working group
#   colleague           Iris Calloway, Product Design; contributes to Fraud Detection Engine
# Any other key is a person reference from the spec, for example "member:web:2".
module DemoHelpers
  PRIMARY = "northline-financial"
  FOREIGN = "memento-ai"

  def self.spec = @spec ||= EnterpriseDemo.spec
  def org(slug = PRIMARY) = Organization.find_by!(slug: slug)
  def person(key, slug = PRIMARY)
    ref = EnterpriseDemo.company(DemoHelpers.spec, slug).fetch("personas").fetch(key.to_s, key.to_s)
    User.find(EnterpriseDemo.person_id(slug, ref))
  end
  def headcount(slug = PRIMARY) = EnterpriseDemo.people(DemoHelpers.spec, EnterpriseDemo.company(DemoHelpers.spec, slug)).size
  def team(key, slug = PRIMARY) = OrganizationalUnit.find(DemoData.uuid("#{slug}/unit/#{key}"))
  def project(key = "fraud-detection-engine", slug = PRIMARY) = Project.find_by!(organization: org(slug), slug: key)
  def json = response.parsed_body
  def data = json.fetch("data")
  def origin_headers = { "Origin" => "http://localhost:3000" }
  def sign_in(key, slug = PRIMARY)
    post "/api/v1/demo/sessions", params: { user_id: person(key, slug).id }, headers: origin_headers, as: :json
    expect(response).to have_http_status(:created)
  end
end

RSpec.configure { |config| config.include DemoHelpers }
