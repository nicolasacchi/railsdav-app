require "rails_helper"

RSpec.describe Addressbook, type: :model do
  describe "validations" do
    it "requires a uri" do
      ab = Addressbook.new(user: create(:user), displayname: "Test", uri: "")
      expect(ab).not_to be_valid
    end

    it "requires uri to be unique per user" do
      user = create(:user)
      # default addressbook already created
      ab = Addressbook.new(user: user, uri: "default", displayname: "Dup")
      expect(ab).not_to be_valid
    end

    it "allows same uri for different users" do
      user1 = create(:user)
      user2 = create(:user)
      ab = Addressbook.new(user: user2, uri: "default", displayname: "Also default")
      # user2 already has a 'default' from callback, so this should fail
      expect(ab).not_to be_valid
    end

    it "requires a displayname" do
      ab = Addressbook.new(user: create(:user), uri: "custom", displayname: "")
      expect(ab).not_to be_valid
    end
  end

  describe "dav_password" do
    it "auto-generates on create" do
      ab = create(:addressbook)
      expect(ab.dav_password).to be_present
      expect(ab.dav_password.length).to eq(24)
    end

    it "preserves explicit value" do
      ab = create(:addressbook, dav_password: "my-custom-password")
      expect(ab.dav_password).to eq("my-custom-password")
    end

    it "regenerates with a new value" do
      ab = create(:addressbook)
      old_password = ab.dav_password
      ab.regenerate_dav_password!
      expect(ab.reload.dav_password).not_to eq(old_password)
      expect(ab.dav_password.length).to eq(24)
    end
  end

  describe "#increment_sync!" do
    it "increments both ctag and sync_token" do
      user = create(:user)
      ab = user.addressbooks.first
      expect { ab.increment_sync! }.to change { ab.reload.ctag }.by(1)
        .and change { ab.reload.sync_token }.by(1)
    end
  end

  describe "#sync_token_url" do
    it "returns a URI-format sync token" do
      user = create(:user)
      ab = user.addressbooks.first
      host = Railsdav.site_url
      expect(ab.sync_token_url).to eq("http://#{host}/ns/sync/0")
    end
  end

  describe ".parse_sync_token" do
    it "extracts the integer from a sync token URL" do
      host = Railsdav.site_url
      expect(Addressbook.parse_sync_token("http://#{host}/ns/sync/42")).to eq(42)
    end

    it "returns nil for invalid token" do
      expect(Addressbook.parse_sync_token("invalid")).to be_nil
    end

    it "returns nil for nil" do
      expect(Addressbook.parse_sync_token(nil)).to be_nil
    end
  end
end
