require "rails_helper"

RSpec.describe "Api::ContactPolicies", type: :request do
  let(:token) { "secret-token-abc123-with-some-length" }
  let(:auth_header) { { "Authorization" => "Bearer #{token}" } }
  let(:user) { create(:user, username: "callscreen-bot") }

  before do
    ENV["CALLSCREEN_API_TOKEN"] = token
    ENV["CALLSCREEN_API_USERNAME"] = user.username
    user # ensure default addressbook exists
  end

  after do
    ENV.delete("CALLSCREEN_API_TOKEN")
    ENV.delete("CALLSCREEN_API_USERNAME")
  end

  def make_contact(phone:, policy: nil)
    book = user.addressbooks.first
    vcard = "BEGIN:VCARD\r\nVERSION:3.0\r\nUID:uid-#{SecureRandom.hex(4)}\r\nFN:Caller\r\nTEL:#{phone}\r\nEND:VCARD\r\n"
    create(:contact, addressbook: book, uri: "#{SecureRandom.uuid}.vcf", vcard_data: vcard, call_screening_policy: policy)
  end

  describe "POST /api/contacts/set_policy" do
    it "rejects an invalid policy" do
      post "/api/contacts/set_policy", params: { phone: "+393331234567", policy: "bogus" }, headers: auth_header
      expect(response).to have_http_status(:unprocessable_content)
      expect(JSON.parse(response.body)).to include("error" => "invalid_policy")
    end

    it "rejects an invalid phone" do
      post "/api/contacts/set_policy", params: { phone: "not-a-number", policy: "block" }, headers: auth_header
      expect(response).to have_http_status(:unprocessable_content)
      expect(JSON.parse(response.body)).to include("error" => "invalid_phone")
    end

    it "blocks an existing contact" do
      contact = make_contact(phone: "+393331234567", policy: "screen")

      post "/api/contacts/set_policy", params: { phone: "+393331234567", policy: "block" }, headers: auth_header

      expect(response).to have_http_status(:ok)
      body = JSON.parse(response.body)
      expect(body).to include("ok" => true, "policy" => "block", "created" => false)
      expect(contact.reload.call_screening_policy).to eq("block")
    end

    it "creates a blocking contact for an unknown number" do
      expect {
        post "/api/contacts/set_policy", params: { phone: "+393339999999", policy: "block", name: "Scammer" }, headers: auth_header
      }.to change { user.addressbooks.first.contacts.count }.by(1)

      expect(response).to have_http_status(:ok)
      body = JSON.parse(response.body)
      expect(body).to include("policy" => "block", "created" => true)
    end

    it "records a sync change so DAV clients pick it up" do
      make_contact(phone: "+393331234567", policy: "screen")
      book = user.addressbooks.first

      expect {
        post "/api/contacts/set_policy", params: { phone: "+393331234567", policy: "block" }, headers: auth_header
      }.to change { book.reload.sync_changes.count }.by_at_least(1)
    end
  end
end
