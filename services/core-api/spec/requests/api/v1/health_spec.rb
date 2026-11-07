require "rails_helper"

RSpec.describe "GET /api/v1/health", type: :request do
  it "checks PostgreSQL and returns the JSON health contract" do
    get "/api/v1/health"
    expect(response).to have_http_status(:ok)
    expect(response.media_type).to eq("application/json")
    expect(response.parsed_body).to eq("service" => "core-api", "status" => "ok", "database" => "connected")
    expect(response.headers["Cache-Control"]).to include("no-store")
  end

  [ActiveRecord::ConnectionNotEstablished, ActiveRecord::StatementInvalid, ActiveRecord::ConnectionTimeoutError].each do |error|
    it "returns unavailable JSON for #{error.name}" do
      allow(ActiveRecord::Base.connection_pool).to receive(:with_connection).and_raise(error, "private connection details")
      get "/api/v1/health"
      expect(response).to have_http_status(:service_unavailable)
      expect(response.media_type).to eq("application/json")
      expect(response.parsed_body).to eq("service" => "core-api", "status" => "error", "database" => "disconnected")
      expect(response.body).not_to include("private connection details")
    end
  end

  it "permits only the configured frontend origin" do
    get "/api/v1/health", headers: { "Origin" => ENV.fetch("FRONTEND_ORIGIN", "http://localhost:3000") }
    expect(response.headers["Access-Control-Allow-Origin"]).to eq(ENV.fetch("FRONTEND_ORIGIN", "http://localhost:3000"))
    get "/api/v1/health", headers: { "Origin" => "https://unrelated.example" }
    expect(response.headers).not_to have_key("Access-Control-Allow-Origin")
  end
end
