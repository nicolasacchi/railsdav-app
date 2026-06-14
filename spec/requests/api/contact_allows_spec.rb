require "rails_helper"

RSpec.describe "Api::ContactAllows", type: :request do
  let(:token) { "secret-token-abc123-with-some-length" }
  let(:auth_header) { { "Authorization" => "Bearer #{token}" } }
  let(:user) { create(:user, username: "callscreen-bot") }
  # User auto-creates a "default" addressbook on create (after_create).
  let(:book) { user.addressbooks.find_by!(uri: "default") }

  before do
    ENV["CALLSCREEN_API_TOKEN"] = token
    ENV["CALLSCREEN_API_USERNAME"] = user.username
  end

  after do
    ENV.delete("CALLSCREEN_API_TOKEN")
    ENV.delete("CALLSCREEN_API_USERNAME")
  end

  describe "POST /api/contacts/upsert_allow" do
    it "401 without a valid bearer token" do
      post "/api/contacts/upsert_allow", params: { phone: "+393331234567" }
      expect(response).to have_http_status(:unauthorized)
    end

    it "422 for a non-E.164 phone" do
      post "/api/contacts/upsert_allow", params: { phone: "anonymous" }, headers: auth_header
      expect(response).to have_http_status(:unprocessable_entity)
    end

    it "creates an allow contact when the number is unknown" do
      book # ensure the default book exists
      expect {
        post "/api/contacts/upsert_allow",
             params: { phone: "+393331234567", name: "Trusted Caller" }, headers: auth_header
      }.to change(Contact, :count).by(1)

      expect(response).to have_http_status(:ok)
      body = JSON.parse(response.body)
      expect(body).to include("ok" => true, "policy" => "allow", "created" => true)
      contact = Contact.find(body["contact_id"])
      expect(contact.call_screening_policy).to eq("allow")
      expect(contact.contact_phone_numbers.pluck(:e164)).to include("+393331234567")
    end

    it "sets an existing contact to allow without creating a duplicate (national-format input)" do
      vcard = "BEGIN:VCARD\r\nVERSION:3.0\r\nUID:uid-existing\r\nFN:Mario\r\nN:Mario;;;;\r\n" \
              "TEL:+393331234567\r\nEND:VCARD\r\n"
      existing = create(:contact, addressbook: book, uri: "#{SecureRandom.uuid}.vcf",
                        vcard_data: vcard, call_screening_policy: "screen")

      expect {
        post "/api/contacts/upsert_allow", params: { phone: "333 123 4567" }, headers: auth_header
      }.not_to change(Contact, :count)

      expect(JSON.parse(response.body)["contact_id"]).to eq(existing.id)
      expect(existing.reload.call_screening_policy).to eq("allow")
    end

    it "records a CardDAV sync change so the operator's address-book clients see it" do
      expect {
        post "/api/contacts/upsert_allow", params: { phone: "+393331234567" }, headers: auth_header
      }.to change { book.reload.sync_changes.count }.by(1)
    end

    it "does not touch another user's contact (scoped to the resolved user)" do
      other = create(:user, username: "someone-else")
      other_book = other.addressbooks.find_by!(uri: "default")
      vcard = "BEGIN:VCARD\r\nVERSION:3.0\r\nUID:uid-other\r\nFN:Stranger\r\nN:Stranger;;;;\r\n" \
              "TEL:+393331234567\r\nEND:VCARD\r\n"
      stranger = create(:contact, addressbook: other_book, uri: "#{SecureRandom.uuid}.vcf",
                        vcard_data: vcard, call_screening_policy: "screen")

      post "/api/contacts/upsert_allow", params: { phone: "+393331234567" }, headers: auth_header

      # A new contact is created in OUR book; the stranger's is untouched.
      expect(response).to have_http_status(:ok)
      expect(stranger.reload.call_screening_policy).to eq("screen")
    end
  end
end
