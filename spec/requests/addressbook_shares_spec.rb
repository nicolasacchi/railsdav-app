require "rails_helper"

RSpec.describe "AddressbookShares", type: :request do
  let(:owner) { create(:user) }
  let(:other_user) { create(:user) }
  let(:addressbook) { owner.addressbooks.first }

  before do
    post login_path, params: { email: owner.email, password: "password123" }
  end

  describe "POST /addressbooks/:uri/shares" do
    it "creates a pending share for existing user" do
      post addressbook_shares_path(addressbook.uri), params: { email: other_user.email, permission: "read" }
      expect(response).to redirect_to(addressbook_path(addressbook.uri))
      share = addressbook.shares.find_by(user: other_user)
      expect(share).to be_present
      expect(share.permission).to eq("read")
      expect(share.status).to eq("pending")
    end

    it "creates a pending share with write permission" do
      post addressbook_shares_path(addressbook.uri), params: { email: other_user.email, permission: "write" }
      share = addressbook.shares.find_by(user: other_user)
      expect(share.permission).to eq("write")
      expect(share.status).to eq("pending")
    end

    it "creates a pending invitation for unregistered email" do
      post addressbook_shares_path(addressbook.uri), params: { email: "newperson@example.com", permission: "read" }
      expect(response).to redirect_to(addressbook_path(addressbook.uri))
      share = addressbook.shares.find_by(invited_email: "newperson@example.com")
      expect(share).to be_present
      expect(share.status).to eq("pending")
      expect(share.user_id).to be_nil
    end

    it "rejects sharing with yourself" do
      post addressbook_shares_path(addressbook.uri), params: { email: owner.email }
      expect(flash[:alert]).to include("Cannot share with yourself")
    end

    it "rejects invalid email" do
      post addressbook_shares_path(addressbook.uri), params: { email: "not-an-email" }
      expect(flash[:alert]).to include("valid email")
    end

    it "sends invitation email for existing user" do
      expect {
        post addressbook_shares_path(addressbook.uri), params: { email: other_user.email }
      }.to change { ActionMailer::Base.deliveries.count }.by(1)
    end

    it "sends invitation email for new user" do
      expect {
        post addressbook_shares_path(addressbook.uri), params: { email: "brand-new@example.com" }
      }.to change { ActionMailer::Base.deliveries.count }.by(1)
    end
  end

  describe "DELETE /addressbooks/:uri/shares/:id" do
    it "removes a share" do
      share = create(:addressbook_share, addressbook: addressbook, user: other_user)
      expect {
        delete addressbook_share_path(addressbook.uri, share)
      }.to change(AddressbookShare, :count).by(-1)
    end
  end

  describe "POST /addressbooks/:uri/create_public_link" do
    it "creates a public link" do
      expect {
        post create_public_link_addressbook_path(addressbook.uri)
      }.to change { addressbook.shares.public_links.count }.by(1)
    end

    it "is idempotent" do
      post create_public_link_addressbook_path(addressbook.uri)
      expect {
        post create_public_link_addressbook_path(addressbook.uri)
      }.not_to change { addressbook.shares.public_links.count }
    end
  end

  describe "DELETE /addressbooks/:uri/destroy_public_link" do
    it "removes public link" do
      create(:addressbook_share, :public_link, addressbook: addressbook)
      expect {
        delete destroy_public_link_addressbook_path(addressbook.uri)
      }.to change { addressbook.shares.public_links.count }.by(-1)
    end
  end
end
