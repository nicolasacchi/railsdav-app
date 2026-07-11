require "rails_helper"

RSpec.describe "Api::SpamNumbers index", type: :request do
  let(:token) { "secret-token-abc123-with-some-length" }
  let(:auth_header) { { "Authorization" => "Bearer #{token}" } }

  before { ENV["CALLSCREEN_API_TOKEN"] = token }
  after  { ENV.delete("CALLSCREEN_API_TOKEN") }

  describe "GET /api/spam_numbers" do
    it "requires authentication" do
      get "/api/spam_numbers"
      expect(response).to have_http_status(:unauthorized)
    end

    it "lists spam numbers with metadata and pagination fields" do
      create(:spam_number, phone: "+393330000001", source: "manual", report_count: 2)

      get "/api/spam_numbers", headers: auth_header

      expect(response).to have_http_status(:ok)
      body = JSON.parse(response.body)
      expect(body["ok"]).to be(true)
      expect(body).to include("page", "per_page", "total")
      expect(body["numbers"].first).to include(
        "phone" => "+393330000001",
        "source" => "manual",
        "report_count" => 2
      )
    end

    it "filters to active-only when requested" do
      create(:spam_number, phone: "+393330000002", report_count: 1, last_seen_at: 3.years.ago, first_reported_at: 3.years.ago)
      create(:spam_number, phone: "+393330000003", report_count: 5)

      get "/api/spam_numbers", params: { active_only: "true" }, headers: auth_header

      phones = JSON.parse(response.body)["numbers"].map { |n| n["phone"] }
      expect(phones).to include("+393330000003")
      expect(phones).not_to include("+393330000002")
    end

    it "supports incremental pulls via ?since=" do
      old = create(:spam_number, phone: "+393330000004", last_seen_at: 10.days.ago, first_reported_at: 10.days.ago)
      fresh = create(:spam_number, phone: "+393330000005", last_seen_at: 1.hour.ago)

      get "/api/spam_numbers", params: { since: 2.days.ago.iso8601 }, headers: auth_header

      phones = JSON.parse(response.body)["numbers"].map { |n| n["phone"] }
      expect(phones).to include(fresh.phone)
      expect(phones).not_to include(old.phone)
    end
  end
end
