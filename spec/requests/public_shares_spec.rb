require "rails_helper"

RSpec.describe "PublicShares", type: :request do
  let(:owner) { create(:user) }
  let(:addressbook) { owner.addressbooks.first }

  describe "GET /s/:token" do
    it "shows the shared addressbook" do
      share = create(:addressbook_share, :public_link, addressbook: addressbook)
      addressbook.contacts.create!(uri: "test.vcf", vcard_data: "BEGIN:VCARD\r\nVERSION:3.0\r\nFN:Test Person\r\nUID:test-uid\r\nEND:VCARD\r\n")

      get public_share_path(share.token)
      expect(response).to have_http_status(:ok)
      expect(response.body).to include(addressbook.displayname)
      expect(response.body).to include("Test Person")
    end

    it "returns 404 for invalid token" do
      get public_share_path("invalid-token")
      expect(response).to have_http_status(:not_found)
    end

    it "does not require login" do
      share = create(:addressbook_share, :public_link, addressbook: addressbook)
      get public_share_path(share.token)
      expect(response).to have_http_status(:ok)
    end
  end
end
