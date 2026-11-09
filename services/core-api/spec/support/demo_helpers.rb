module DemoHelpers
  def org(slug = "aperture-technologies") = Organization.find_by!(slug: slug)
  def person(key, slug = "aperture-technologies") = User.find_by!(email: "#{key}@#{slug}.example")
  def team(key) = OrganizationalUnit.find(DemoData.uuid("aperture-technologies/unit/#{key}"))
  def project(key = "fraud-detection") = Project.find_by!(organization: org, slug: key)
  def json = response.parsed_body
  def data = json.fetch("data")
  def origin_headers = { "Origin" => "http://localhost:3000" }
  def sign_in(key, slug = "aperture-technologies")
    post "/api/v1/demo/sessions", params: { user_id: person(key, slug).id }, headers: origin_headers, as: :json
    expect(response).to have_http_status(:created)
  end
end

RSpec.configure { |config| config.include DemoHelpers }
