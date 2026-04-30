require "rails_helper"

RSpec.describe Contacts::PhoneLookup do
  let(:user) { create(:user) }
  let(:addressbook) { create(:addressbook, user: user, call_screening_policy: "screen") }

  def make_contact(addressbook:, phone:, policy: nil, name: "Alice")
    vcard = "BEGIN:VCARD\r\nVERSION:3.0\r\nUID:uid-#{SecureRandom.hex(4)}\r\nFN:#{name}\r\nN:#{name};;;;\r\nTEL:#{phone}\r\nEND:VCARD\r\n"
    create(:contact,
      addressbook: addressbook,
      uri: "#{SecureRandom.uuid}.vcf",
      vcard_data: vcard,
      call_screening_policy: policy
    )
  end

  describe ".find_by_e164" do
    it "returns nil for blank input" do
      expect(described_class.find_by_e164("", user: user)).to be_nil
      expect(described_class.find_by_e164(nil, user: user)).to be_nil
    end

    it "returns nil for non-string input" do
      expect(described_class.find_by_e164([ "+393331234567" ], user: user)).to be_nil
      expect(described_class.find_by_e164({ value: "+393331234567" }, user: user)).to be_nil
    end

    it "returns nil for an invalid number" do
      expect(described_class.find_by_e164("not-a-number", user: user)).to be_nil
    end

    it "returns nil when user is nil" do
      make_contact(addressbook: addressbook, phone: "+393331234567")
      expect(described_class.find_by_e164("+393331234567", user: nil)).to be_nil
    end

    it "returns nil when no contact has the phone" do
      make_contact(addressbook: addressbook, phone: "+393331234567")
      expect(described_class.find_by_e164("+393339999999", user: user)).to be_nil
    end

    it "matches a contact by exact E.164 phone" do
      make_contact(addressbook: addressbook, phone: "+393331234567", name: "Bob")
      result = described_class.find_by_e164("+393331234567", user: user)
      expect(result).not_to be_nil
      expect(result.contact.cached_display_name).to eq("Bob")
      expect(result.policy).to eq("screen")
    end

    it "normalizes input numbers using PHONE_DEFAULT_COUNTRY before matching" do
      make_contact(addressbook: addressbook, phone: "+393331234567")
      result = described_class.find_by_e164("333 123 4567", user: user) # local Italian format
      expect(result).not_to be_nil
    end

    it "uses contact-level policy when set, ignoring addressbook policy" do
      ab = create(:addressbook, user: user, call_screening_policy: "allow")
      make_contact(addressbook: ab, phone: "+393331234567", policy: "block")
      result = described_class.find_by_e164("+393331234567", user: user)
      expect(result.policy).to eq("block")
    end

    it "falls back to addressbook policy when contact policy is nil" do
      ab = create(:addressbook, user: user, call_screening_policy: "allow")
      make_contact(addressbook: ab, phone: "+393331234567", policy: nil)
      result = described_class.find_by_e164("+393331234567", user: user)
      expect(result.policy).to eq("allow")
    end

    it "prefers the strictest policy when the same number appears in multiple of the user's addressbooks (block > allow > screen)" do
      ab_allow = create(:addressbook, user: user, call_screening_policy: "allow", uri: "ab-a")
      ab_block = create(:addressbook, user: user, call_screening_policy: "block", uri: "ab-b")
      make_contact(addressbook: ab_allow, phone: "+393331234567")
      make_contact(addressbook: ab_block, phone: "+393331234567")
      result = described_class.find_by_e164("+393331234567", user: user)
      expect(result.policy).to eq("block")
    end

    it "scopes to the given user's addressbooks (does not leak from other users)" do
      other_user = create(:user)
      other_ab = create(:addressbook, user: other_user, call_screening_policy: "allow")
      make_contact(addressbook: other_ab, phone: "+393331234567", name: "Stranger")

      expect(described_class.find_by_e164("+393331234567", user: user)).to be_nil
      expect(described_class.find_by_e164("+393331234567", user: other_user)).not_to be_nil
    end

    it "ignores shared (non-owned) addressbooks for the lookup user" do
      sharer = create(:user)
      sharer_ab = create(:addressbook, user: sharer, call_screening_policy: "allow")
      create(:addressbook_share, addressbook: sharer_ab, user: user, permission: "write")
      make_contact(addressbook: sharer_ab, phone: "+393331234567", name: "Sharer Contact")

      expect(described_class.find_by_e164("+393331234567", user: user)).to be_nil
    end

    it "ignores encrypted contacts (their phones are not synced)" do
      vcard = Base64.strict_encode64("ciphertext")
      create(:contact,
        addressbook: addressbook,
        uri: "enc.vcf",
        uid: "enc-uid",
        encrypted: true,
        vcard_data: vcard,
        etag: "\"etag\""
      )
      expect(described_class.find_by_e164("+393331234567", user: user)).to be_nil
    end
  end
end
