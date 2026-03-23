require "rails_helper"

RSpec.describe AddressbookShare, type: :model do
  describe "validations" do
    it "requires a valid permission" do
      share = build(:addressbook_share, permission: "invalid")
      expect(share).not_to be_valid
    end

    it "accepts read permission" do
      share = build(:addressbook_share, permission: "read")
      expect(share).to be_valid
    end

    it "accepts write permission for user shares" do
      share = create(:addressbook_share, permission: "write")
      expect(share).to be_valid
    end

    it "enforces uniqueness per addressbook+user" do
      share = create(:addressbook_share)
      duplicate = build(:addressbook_share, addressbook: share.addressbook, user: share.user)
      expect(duplicate).not_to be_valid
    end

    it "requires public links to be read-only" do
      share = build(:addressbook_share, :public_link, permission: "write")
      expect(share).not_to be_valid
      expect(share.errors[:permission]).to be_present
    end
  end

  describe "token generation" do
    it "auto-generates token for public links" do
      ab = create(:addressbook)
      share = ab.shares.create!(permission: "read")
      expect(share.token).to be_present
      expect(share.public_link?).to be true
    end

    it "does not generate token for user shares" do
      share = create(:addressbook_share)
      expect(share.token).to be_nil
      expect(share.public_link?).to be false
    end
  end

  describe "#writable?" do
    it "returns true for write permission" do
      share = build(:addressbook_share, :write)
      expect(share.writable?).to be true
    end

    it "returns false for read permission" do
      share = build(:addressbook_share, permission: "read")
      expect(share.writable?).to be false
    end
  end

  describe "scopes" do
    it ".for_user returns shares for a specific user" do
      user = create(:user)
      share = create(:addressbook_share, user: user)
      create(:addressbook_share) # different user
      expect(AddressbookShare.for_user(user)).to eq([ share ])
    end

    it ".public_links returns only public shares" do
      create(:addressbook_share) # user share
      public_share = create(:addressbook_share, :public_link)
      expect(AddressbookShare.public_links).to eq([ public_share ])
    end
  end
end
