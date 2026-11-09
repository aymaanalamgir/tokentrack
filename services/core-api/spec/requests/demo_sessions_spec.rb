require "rails_helper"

RSpec.describe "Demo authentication", type: :request do
  it "lists only active explicitly flagged fictional identities without private fields" do
    person("casey").update!(demo_identity: false)
    get "/api/v1/demo/identities"
    expect(response).to have_http_status(:ok)
    expect(data.size).to eq(73)
    expect(data.map { |u| u["id"] }).not_to include(person("casey").id)
    expect(data.first).not_to have_key("email")
  end

  it "requires a backend session and ignores arbitrary identity/role headers" do
    get "/api/v1/me", headers: { "X-User-Id" => person("olivia").id, "X-Role" => "organization_viewer" }
    expect(response).to have_http_status(:unauthorized)
  end

  it "creates an HTTP-only same-site session with only a token digest stored" do
    sign_in("jordan")
    cookie = response.headers["Set-Cookie"].to_s
    expect(cookie.downcase).to include("httponly", "samesite=lax")
    token = cookies[DemoSession::COOKIE]
    expect(DemoSession.find_by!(token_digest: Digest::SHA256.hexdigest(token)).user).to eq(person("jordan"))
    expect(DemoSession.last.attributes.values).not_to include(token)
    get "/api/v1/me"
    expect(data["user"]["id"]).to eq(person("jordan").id)
    expect(response.headers["Cache-Control"]).to include("no-store")
  end

  it "rotates and revokes the previous identity's session on switching" do
    sign_in("olivia")
    old_token = cookies[DemoSession::COOKIE]
    sign_in("jordan")
    expect(DemoSession.resolve(old_token)).to be_nil
    expect(cookies[DemoSession::COOKIE]).not_to eq(old_token)
    get "/api/v1/me"
    expect(data["access"]["persona"]).to eq("employee")
    expect(data["access"]["navigation"].map { |n| n["href"] }).not_to include("/teams")
  end

  it "does not trust client-supplied role or organization fields" do
    post "/api/v1/demo/sessions", params: { user_id: person("jordan").id, role: "organization_viewer", organization_id: org("northstar-labs").id }, headers: origin_headers, as: :json
    expect(response).to have_http_status(:created)
    get "/api/v1/me"
    expect(data["organization"]["id"]).to eq(org.id)
    expect(data["access"]["persona"]).to eq("employee")
  end

  it "rejects unknown and unflagged identities without destroying a valid session" do
    sign_in("jordan")
    [SecureRandom.uuid, person("casey").tap { |u| u.update!(demo_identity: false) }.id].each do |id|
      post "/api/v1/demo/sessions", params: { user_id: id }, headers: origin_headers, as: :json
      expect(response).to have_http_status(:not_found)
    end
    get "/api/v1/me"
    expect(data["user"]["id"]).to eq(person("jordan").id)
  end

  it "rejects missing or foreign origins on session mutations" do
    [nil, "https://evil.example"].each do |origin|
      post "/api/v1/demo/sessions", params: { user_id: person("olivia").id }, headers: origin ? { "Origin" => origin } : {}, as: :json
      expect(response).to have_http_status(:forbidden)
    end
    expect(DemoSession.count).to eq(0)
  end

  it "logs out and revokes the server-side session" do
    sign_in("jordan")
    token = cookies[DemoSession::COOKIE]
    delete "/api/v1/demo/session", headers: origin_headers, params: {}, as: :json
    expect(response).to have_http_status(:ok)
    expect(DemoSession.resolve(token)).to be_nil
    get "/api/v1/me"
    expect(response).to have_http_status(:unauthorized)
  end

  it "rejects expired sessions and inactive participants" do
    sign_in("jordan")
    DemoSession.update_all(expires_at: 1.minute.ago)
    get "/api/v1/me"
    expect(response).to have_http_status(:unauthorized)
    sign_in("jordan")
    person("jordan").update!(status: "inactive")
    get "/api/v1/me"
    expect(response).to have_http_status(:unauthorized)
  end

  it "disables demo entry when the feature flag is off" do
    previous = ENV["DEMO_AUTH_ENABLED"]
    ENV["DEMO_AUTH_ENABLED"] = "false"
    get "/api/v1/demo/identities"
    expect(response).to have_http_status(:not_found)
    post "/api/v1/demo/sessions", params: { user_id: person("olivia").id }, headers: origin_headers, as: :json
    expect(response).to have_http_status(:not_found)
  ensure
    ENV["DEMO_AUTH_ENABLED"] = previous
  end

  it "cannot be enabled in production, even with the feature flag" do
    allow(Rails).to receive(:env).and_return(ActiveSupport::StringInquirer.new("production"))
    expect(DemoSession.enabled?).to be(false)
    get "/api/v1/demo/identities"
    expect(response).to have_http_status(:not_found)
  end
end
