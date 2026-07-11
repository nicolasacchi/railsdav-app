require "rails_helper"

RSpec.describe "Api::ContactLookups bulk", type: :request do
  let(:token) { "secret-token-abc123-with-some-length" }
  let(:auth_header) { { "Authorization" => "Bearer #{token}" } }
  let(:user) { create(:user, username: "callscreen-bot") }
  let(:addressbook) { create(:addressbook, user: user, call_screening_policy: "screen") }

  before do
    ENV["CALLSCREEN_API_TOKEN"] = token
    ENV["CALLSCREEN_API_USERNAME"] = user.username
  end

  after do
    ENV.delete("CALLSCREEN_API_TOKEN")
    ENV.delete("CALLSCREEN_API_USERNAME")
  end

  def make_contact(phone:, name: "Alice")
    vcard = "BEGIN:VCARD\r\nVERSION:3.0\r\nUID:uid-#{SecureRandom.hex(4)}\r\nFN:#{name}\r\nTEL:#{phone}\r\nEND:VCARD\r\n"
    create(:contact, addressbook: addressbook, uri: "#{SecureRandom.uuid}.vcf", vcard_data: vcard)
  end

  describe "POST /api/contact_lookup/bulk" do
    it "requires authentication" do
      post "/api/contact_lookup/bulk", params: { phones: ["+393331234567"] }
      expect(response).to have_http_status(:unauthorized)
    end

    it "returns a result per phone with match state" do
      make_contact(phone: "+393331234567", name: "Known")
      create(:spam_number, phone: "+393330000000", report_count: 4)

      post "/api/contact_lookup/bulk",
           params: { phones: ["+393331234567", "+393330000000", "+393335550000"] },
           headers: auth_header

      expect(response).to have_http_status(:ok)
      body = JSON.parse(response.body)
      expect(body["ok"]).to be(true)
      expect(body["count"]).to eq(3)

      by_phone = body["results"].index_by { |r| r["phone"] }
      expect(by_phone["+393331234567"]).to include("match" => true, "name" => "Known")
      expect(by_phone["+393330000000"]).to include("match" => false, "spam_global" => true)
      expect(by_phone["+393335550000"]).to include("match" => false, "spam_global" => false)
    end

    it "caps the batch and flags truncation" do
      phones = Array.new(Api::ContactLookupsController::MAX_BULK + 5) { |i| "+3933300#{i.to_s.rjust(5, '0')}" }

      post "/api/contact_lookup/bulk", params: { phones: phones }, headers: auth_header

      body = JSON.parse(response.body)
      expect(body["count"]).to eq(Api::ContactLookupsController::MAX_BULK)
      expect(body["truncated"]).to be(true)
    end
  end
end
