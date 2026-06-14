require "rails_helper"

RSpec.describe "Api::Health", type: :request do
  let(:token) { "secret-token-abc123-with-some-length" }
  let(:auth_header) { { "Authorization" => "Bearer #{token}" } }

  before { ENV["CALLSCREEN_API_TOKEN"] = token }
  after  { ENV.delete("CALLSCREEN_API_TOKEN") }

  describe "GET /api/health" do
    it "returns 401 without a valid bearer token (Bearer-gated like the rest of the API)" do
      get "/api/health"
      expect(response).to have_http_status(:unauthorized)
    end

    it "returns ok + the spam_numbers count when authenticated" do
      SpamNumber.upsert_report!(phone: "+393331234567", source: "manual")
      get "/api/health", headers: auth_header
      expect(response).to have_http_status(:ok)
      body = JSON.parse(response.body)
      expect(body["ok"]).to eq(true)
      expect(body["spam_count"]).to eq(1)
    end
  end
end
