require "rails_helper"

RSpec.describe "Api::SpamReports", type: :request do
  let(:token) { "secret-token-abc123-with-some-length" }
  let(:auth_header) { { "Authorization" => "Bearer #{token}" } }
  let(:phone) { "+393331234567" }

  before { ENV["CALLSCREEN_API_TOKEN"] = token }
  after  { ENV.delete("CALLSCREEN_API_TOKEN") }

  describe "POST /api/spam_reports" do
    it "returns 401 with no Authorization header" do
      post "/api/spam_reports", params: { phone: phone }
      expect(response).to have_http_status(:unauthorized)
    end

    it "returns 401 with a wrong bearer token" do
      post "/api/spam_reports",
           params: { phone: phone },
           headers: { "Authorization" => "Bearer wrong" }
      expect(response).to have_http_status(:unauthorized)
    end

    it "returns 401 with a token of different length (no length leak)" do
      post "/api/spam_reports",
           params: { phone: phone },
           headers: { "Authorization" => "Bearer " + ("x" * 5) }
      expect(response).to have_http_status(:unauthorized)
    end

    it "returns 503 when CALLSCREEN_API_TOKEN is unset" do
      ENV.delete("CALLSCREEN_API_TOKEN")
      post "/api/spam_reports", params: { phone: phone }, headers: auth_header
      expect(response).to have_http_status(:service_unavailable)
    end

    it "creates a SpamNumber on first report and returns 200" do
      expect {
        post "/api/spam_reports",
             params: { phone: phone, source: "ntfy_report", submitted_by_username: "nicola" },
             headers: auth_header
      }.to change(SpamNumber, :count).by(1)

      expect(response).to have_http_status(:ok)
      expect(JSON.parse(response.body)).to eq("ok" => true)

      sn = SpamNumber.find_by!(phone: phone)
      expect(sn.source).to eq("ntfy_report")
      expect(sn.submitted_by_username).to eq("nicola")
      expect(sn.report_count).to eq(1)
    end

    it "is idempotent: a second report bumps report_count to 2" do
      post "/api/spam_reports", params: { phone: phone, source: "ntfy_report" }, headers: auth_header
      expect {
        post "/api/spam_reports", params: { phone: phone, source: "ntfy_report" }, headers: auth_header
      }.not_to change(SpamNumber, :count)

      sn = SpamNumber.find_by!(phone: phone)
      expect(sn.report_count).to eq(2)
    end

    it "normalizes phone before storing (national → E.164)" do
      post "/api/spam_reports", params: { phone: "333 123 4567", source: "manual" }, headers: auth_header
      expect(response).to have_http_status(:ok)
      expect(SpamNumber.find_by(phone: "+393331234567")).to be_present
    end

    it "returns 422 on invalid phone" do
      post "/api/spam_reports", params: { phone: "garbage" }, headers: auth_header
      expect(response).to have_http_status(:unprocessable_entity)
      expect(JSON.parse(response.body)).to eq("ok" => false, "error" => "invalid_phone")
    end

    it "returns 422 on invalid source" do
      post "/api/spam_reports",
           params: { phone: phone, source: "evil" },
           headers: auth_header
      expect(response).to have_http_status(:unprocessable_entity)
      expect(JSON.parse(response.body)).to eq("ok" => false, "error" => "invalid_source")
    end

    it "accepts feed:<id> source" do
      post "/api/spam_reports",
           params: { phone: phone, source: "feed:tellows" },
           headers: auth_header
      expect(response).to have_http_status(:ok)
      expect(SpamNumber.find_by!(phone: phone).source).to eq("feed:tellows")
    end

    it "defaults source to ntfy_report when omitted" do
      post "/api/spam_reports", params: { phone: phone }, headers: auth_header
      expect(response).to have_http_status(:ok)
      expect(SpamNumber.find_by!(phone: phone).source).to eq("ntfy_report")
    end
  end
end
