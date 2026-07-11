require "rails_helper"

RSpec.describe "Api::Metrics", type: :request do
  let(:token) { "secret-token-abc123-with-some-length" }
  let(:auth_header) { { "Authorization" => "Bearer #{token}" } }

  before { ENV["CALLSCREEN_API_TOKEN"] = token }
  after  { ENV.delete("CALLSCREEN_API_TOKEN") }

  describe "GET /api/metrics" do
    it "requires authentication" do
      get "/api/metrics"
      expect(response).to have_http_status(:unauthorized)
    end

    it "returns aggregate counts" do
      user = create(:user)
      book = create(:addressbook, user: user)
      create(:contact, addressbook: book)
      create(:spam_number, report_count: 3)

      get "/api/metrics", headers: auth_header

      expect(response).to have_http_status(:ok)
      body = JSON.parse(response.body)
      expect(body["ok"]).to be(true)
      expect(body["users"]).to be >= 1
      expect(body["contacts"]).to include("total", "individuals", "encrypted")
      expect(body["spam"]).to include("total" => 1, "active" => 1)
    end
  end
end
