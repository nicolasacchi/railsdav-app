require "rails_helper"

RSpec.describe "Api::ContactLookups", type: :request do
  let(:token) { "secret-token-abc123-with-some-length" }
  let(:auth_header) { { "Authorization" => "Bearer #{token}" } }

  let(:user) { create(:user, username: "callscreen-bot") }
  let(:addressbook) { create(:addressbook, user: user, displayname: "Family", call_screening_policy: "screen") }

  before do
    ENV["CALLSCREEN_API_TOKEN"] = token
    ENV["CALLSCREEN_API_USERNAME"] = user.username
  end

  after do
    ENV.delete("CALLSCREEN_API_TOKEN")
    ENV.delete("CALLSCREEN_API_USERNAME")
  end

  def make_contact(phone:, policy: nil, name: "Alice", book: addressbook)
    vcard = "BEGIN:VCARD\r\nVERSION:3.0\r\nUID:uid-#{SecureRandom.hex(4)}\r\nFN:#{name}\r\nN:#{name};;;;\r\nTEL:#{phone}\r\nEND:VCARD\r\n"
    create(:contact,
      addressbook: book,
      uri: "#{SecureRandom.uuid}.vcf",
      vcard_data: vcard,
      call_screening_policy: policy
    )
  end

  describe "GET /api/contact_lookup" do
    it "returns 401 with no Authorization header" do
      get "/api/contact_lookup", params: { phone: "+393331234567" }
      expect(response).to have_http_status(:unauthorized)
    end

    it "returns 401 with a wrong bearer token" do
      get "/api/contact_lookup",
          params: { phone: "+393331234567" },
          headers: { "Authorization" => "Bearer wrong" }
      expect(response).to have_http_status(:unauthorized)
    end

    it "returns 401 with a token of different length (no length leak via early-return)" do
      get "/api/contact_lookup",
          params: { phone: "+393331234567" },
          headers: { "Authorization" => "Bearer " + ("x" * 5) }
      expect(response).to have_http_status(:unauthorized)
    end

    it "returns 503 when the env token is unset" do
      ENV.delete("CALLSCREEN_API_TOKEN")
      get "/api/contact_lookup", params: { phone: "+393331234567" }, headers: auth_header
      expect(response).to have_http_status(:service_unavailable)
    end

    it "returns 503 when CALLSCREEN_API_USERNAME is unset" do
      ENV.delete("CALLSCREEN_API_USERNAME")
      get "/api/contact_lookup", params: { phone: "+393331234567" }, headers: auth_header
      expect(response).to have_http_status(:service_unavailable)
    end

    it "returns 503 when CALLSCREEN_API_USERNAME doesn't match a user" do
      ENV["CALLSCREEN_API_USERNAME"] = "nobody-here"
      get "/api/contact_lookup", params: { phone: "+393331234567" }, headers: auth_header
      expect(response).to have_http_status(:service_unavailable)
    end

    it "returns match: false when the number is unknown" do
      get "/api/contact_lookup", params: { phone: "+393339999999" }, headers: auth_header
      expect(response).to have_http_status(:ok)
      expect(JSON.parse(response.body)).to eq("match" => false)
    end

    it "returns match: false for non-string phone params" do
      get "/api/contact_lookup", params: { phone: [ "+393331234567" ] }, headers: auth_header
      expect(response).to have_http_status(:ok)
      expect(JSON.parse(response.body)).to eq("match" => false)
    end

    it "returns the matched contact and policy" do
      make_contact(phone: "+393331234567", name: "Bob", policy: "allow")
      get "/api/contact_lookup", params: { phone: "+393331234567" }, headers: auth_header
      expect(response).to have_http_status(:ok)
      body = JSON.parse(response.body)
      expect(body["match"]).to eq(true)
      expect(body["name"]).to eq("Bob")
      expect(body["policy"]).to eq("allow")
      expect(body["addressbook"]).to eq("Family")
      expect(body["contact_id"]).to be_a(Integer)
    end

    it "normalizes a national-format number against stored E.164" do
      make_contact(phone: "+393331234567", name: "Bob")
      get "/api/contact_lookup", params: { phone: "333 123 4567" }, headers: auth_header
      body = JSON.parse(response.body)
      expect(body["match"]).to eq(true)
      expect(body["name"]).to eq("Bob")
    end

    it "scopes lookups to the env-configured user (no cross-tenant leakage)" do
      other_user = create(:user, username: "someone-else")
      other_ab = create(:addressbook, user: other_user, displayname: "Other", call_screening_policy: "allow")
      make_contact(phone: "+393331234567", name: "Stranger", book: other_ab)

      get "/api/contact_lookup", params: { phone: "+393331234567" }, headers: auth_header
      expect(JSON.parse(response.body)).to eq("match" => false)
    end

    it "resolves the env username case-sensitively against either username or email" do
      ENV["CALLSCREEN_API_USERNAME"] = user.email
      make_contact(phone: "+393331234567", name: "Bob")

      get "/api/contact_lookup", params: { phone: "+393331234567" }, headers: auth_header
      expect(response).to have_http_status(:ok)
      expect(JSON.parse(response.body)["name"]).to eq("Bob")
    end
  end
end
