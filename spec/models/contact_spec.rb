require "rails_helper"

RSpec.describe Contact, type: :model do
  let(:user) { create(:user) }
  let(:addressbook) { user.addressbooks.first }

  describe "validations" do
    it "requires uri" do
      contact = Contact.new(addressbook: addressbook, vcard_data: "BEGIN:VCARD\nVERSION:3.0\nUID:test\nFN:Test\nEND:VCARD")
      contact.uri = nil
      expect(contact).not_to be_valid
    end

    it "requires uri to be unique per addressbook" do
      Contact.create!(addressbook: addressbook, uri: "test.vcf", uid: "uid1", etag: '"abc"', vcard_data: "BEGIN:VCARD\nVERSION:3.0\nUID:uid1\nFN:Test\nEND:VCARD")
      contact = Contact.new(addressbook: addressbook, uri: "test.vcf", vcard_data: "BEGIN:VCARD\nVERSION:3.0\nUID:uid2\nFN:Test2\nEND:VCARD")
      expect(contact).not_to be_valid
    end

    it "requires vcard_data" do
      contact = Contact.new(addressbook: addressbook, uri: "test.vcf", uid: "uid1", etag: '"abc"')
      expect(contact).not_to be_valid
    end
  end

  describe "before_validation callbacks" do
    it "computes etag from vcard_data as quoted SHA-256" do
      vcard = "BEGIN:VCARD\nVERSION:3.0\nUID:test-uid\nFN:Test\nEND:VCARD"
      contact = Contact.new(addressbook: addressbook, uri: "test.vcf", vcard_data: vcard)
      contact.valid?
      expected = "\"#{Digest::SHA256.hexdigest(vcard)}\""
      expect(contact.etag).to eq(expected)
    end

    it "extracts uid from vcard_data" do
      vcard = "BEGIN:VCARD\nVERSION:3.0\nUID:my-unique-id\nFN:Test\nEND:VCARD"
      contact = Contact.new(addressbook: addressbook, uri: "test.vcf", vcard_data: vcard)
      contact.valid?
      expect(contact.uid).to eq("my-unique-id")
    end

    it "extracts uid with parameters (e.g. UID;VALUE=TEXT:...)" do
      vcard = "BEGIN:VCARD\nVERSION:3.0\nUID;VALUE=TEXT:param-uid\nFN:Test\nEND:VCARD"
      contact = Contact.new(addressbook: addressbook, uri: "test.vcf", vcard_data: vcard)
      contact.valid?
      expect(contact.uid).to eq("param-uid")
    end

    it "updates etag when vcard_data changes" do
      vcard1 = "BEGIN:VCARD\nVERSION:3.0\nUID:test-uid\nFN:Test1\nEND:VCARD"
      vcard2 = "BEGIN:VCARD\nVERSION:3.0\nUID:test-uid\nFN:Test2\nEND:VCARD"
      contact = Contact.create!(addressbook: addressbook, uri: "test.vcf", vcard_data: vcard1)
      old_etag = contact.etag
      contact.update!(vcard_data: vcard2)
      expect(contact.etag).not_to eq(old_etag)
      expect(contact.etag).to eq("\"#{Digest::SHA256.hexdigest(vcard2)}\"")
    end

    it "sets kind to individual for normal contacts" do
      vcard = "BEGIN:VCARD\nVERSION:3.0\nUID:test-uid\nFN:Test\nEND:VCARD"
      contact = Contact.create!(addressbook: addressbook, uri: "test.vcf", vcard_data: vcard)
      expect(contact.kind).to eq("individual")
    end

    it "sets kind to group for KIND:group vCards" do
      vcard = "BEGIN:VCARD\r\nVERSION:3.0\r\nUID:group-uid\r\nKIND:group\r\nFN:Family\r\nN:Family;;;;\r\nEND:VCARD\r\n"
      contact = Contact.create!(addressbook: addressbook, uri: "group.vcf", vcard_data: vcard)
      expect(contact.kind).to eq("group")
    end
  end

  describe "scopes" do
    it "individuals excludes KIND:group contacts" do
      create(:contact, addressbook: addressbook, uid: "ind-1", uri: "ind.vcf")
      group_vcard = "BEGIN:VCARD\r\nVERSION:3.0\r\nUID:grp-1\r\nKIND:group\r\nFN:Family\r\nN:Family;;;;\r\nEND:VCARD\r\n"
      create(:contact, addressbook: addressbook, uid: "grp-1", uri: "grp.vcf", vcard_data: group_vcard)
      expect(addressbook.contacts.individuals.count).to eq(1)
      expect(addressbook.contacts.group_vcards.count).to eq(1)
    end
  end

  describe "sync_groups_from_vcard" do
    it "creates groups from CATEGORIES on save" do
      vcard = "BEGIN:VCARD\r\nVERSION:3.0\r\nUID:cat-uid\r\nFN:Alice\r\nN:Alice;;;;\r\nCATEGORIES:Family,Work\r\nEND:VCARD\r\n"
      contact = Contact.create!(addressbook: addressbook, uri: "cat.vcf", vcard_data: vcard)

      expect(addressbook.contact_groups.pluck(:name)).to match_array(["Family", "Work"])
      expect(contact.contact_groups.pluck(:name)).to match_array(["Family", "Work"])
    end

    it "removes group memberships when CATEGORIES are removed" do
      vcard1 = "BEGIN:VCARD\r\nVERSION:3.0\r\nUID:cat-uid\r\nFN:Alice\r\nCATEGORIES:Family,Work\r\nEND:VCARD\r\n"
      contact = Contact.create!(addressbook: addressbook, uri: "cat.vcf", vcard_data: vcard1)
      expect(contact.contact_groups.count).to eq(2)

      vcard2 = "BEGIN:VCARD\r\nVERSION:3.0\r\nUID:cat-uid\r\nFN:Alice\r\nEND:VCARD\r\n"
      contact.update!(vcard_data: vcard2)
      expect(contact.contact_groups.count).to eq(0)
    end

    it "creates group and links members from KIND:group vCard" do
      member_vcard = "BEGIN:VCARD\r\nVERSION:3.0\r\nUID:member-uid\r\nFN:Bob\r\nN:Bob;;;;\r\nEND:VCARD\r\n"
      member = Contact.create!(addressbook: addressbook, uri: "bob.vcf", vcard_data: member_vcard)

      group_vcard = "BEGIN:VCARD\r\nVERSION:3.0\r\nUID:grp-uid\r\nKIND:group\r\nFN:Team\r\nN:Team;;;;\r\nMEMBER:urn:uuid:member-uid\r\nEND:VCARD\r\n"
      gc = Contact.create!(addressbook: addressbook, uri: "team.vcf", vcard_data: group_vcard)

      group = addressbook.contact_groups.find_by(name: "Team")
      expect(group).to be_present
      expect(group.group_contact).to eq(gc)
      expect(group.contacts).to include(member)
    end

    it "handles X-ADDRESSBOOKSERVER-KIND and X-ADDRESSBOOKSERVER-MEMBER (Apple)" do
      member_vcard = "BEGIN:VCARD\r\nVERSION:3.0\r\nUID:apple-member\r\nFN:Charlie\r\nEND:VCARD\r\n"
      member = Contact.create!(addressbook: addressbook, uri: "charlie.vcf", vcard_data: member_vcard)

      apple_group = "BEGIN:VCARD\r\nVERSION:3.0\r\nUID:apple-grp\r\nX-ADDRESSBOOKSERVER-KIND:group\r\nFN:iCloud Group\r\nN:iCloud Group;;;;\r\nX-ADDRESSBOOKSERVER-MEMBER:urn:uuid:apple-member\r\nEND:VCARD\r\n"
      gc = Contact.create!(addressbook: addressbook, uri: "apple.vcf", vcard_data: apple_group)

      expect(gc.kind).to eq("group")
      group = addressbook.contact_groups.find_by(name: "iCloud Group")
      expect(group).to be_present
      expect(group.contacts).to include(member)
    end
  end

  describe "phone number sync" do
    let(:vcard_with_phones) do
      "BEGIN:VCARD\r\nVERSION:3.0\r\nUID:phone-1\r\nFN:Phone Test\r\nN:Test;Phone;;;\r\nTEL;TYPE=CELL:+393331234567\r\nTEL;TYPE=HOME:+390591234567\r\nEND:VCARD\r\n"
    end

    it "creates ContactPhoneNumber rows on save" do
      contact = Contact.create!(addressbook: addressbook, uri: "phones-1.vcf", vcard_data: vcard_with_phones)
      e164s = contact.contact_phone_numbers.pluck(:e164).sort
      expect(e164s).to eq(["+390591234567", "+393331234567"])
    end

    it "stores the phone type" do
      contact = Contact.create!(addressbook: addressbook, uri: "phones-2.vcf", vcard_data: vcard_with_phones)
      cell = contact.contact_phone_numbers.find_by(e164: "+393331234567")
      expect(cell.phone_type&.upcase).to include("CELL")
    end

    it "replaces phones when vCard changes" do
      contact = Contact.create!(addressbook: addressbook, uri: "phones-3.vcf", vcard_data: vcard_with_phones)
      expect(contact.contact_phone_numbers.count).to eq(2)

      new_vcard = "BEGIN:VCARD\r\nVERSION:3.0\r\nUID:phone-1\r\nFN:Phone Test\r\nN:Test;Phone;;;\r\nTEL:+393331234567\r\nEND:VCARD\r\n"
      contact.update!(vcard_data: new_vcard)
      expect(contact.contact_phone_numbers.pluck(:e164)).to eq(["+393331234567"])
    end

    it "skips invalid phone numbers" do
      vcard = "BEGIN:VCARD\r\nVERSION:3.0\r\nUID:invalid-phone\r\nFN:Bad\r\nN:Bad;;;;\r\nTEL:not-a-phone\r\nTEL:+393331234567\r\nEND:VCARD\r\n"
      contact = Contact.create!(addressbook: addressbook, uri: "phones-bad.vcf", vcard_data: vcard)
      expect(contact.contact_phone_numbers.pluck(:e164)).to eq(["+393331234567"])
    end

    it "skips encrypted contacts" do
      contact = Contact.create!(
        addressbook: addressbook,
        uri: "enc-phones.vcf",
        uid: "enc-uid-x",
        encrypted: true,
        vcard_data: Base64.strict_encode64("ciphertext"),
        etag: "\"e\""
      )
      expect(contact.contact_phone_numbers).to be_empty
    end

    it "enforces a compound unique index on (contact_id, e164)" do
      contact = Contact.create!(addressbook: addressbook, uri: "uniq.vcf", vcard_data: vcard_with_phones)
      expect {
        contact.contact_phone_numbers.create!(e164: "+393331234567")
      }.to raise_error(ActiveRecord::RecordNotUnique)
    end

    it "cascades deletion at the FK level" do
      contact = Contact.create!(addressbook: addressbook, uri: "casc.vcf", vcard_data: vcard_with_phones)
      ContactPhoneNumber.connection.execute("DELETE FROM contacts WHERE id = #{contact.id}")
      expect(ContactPhoneNumber.where(contact_id: contact.id)).to be_empty
    end
  end

  describe "encrypted contacts and screening policy" do
    it "rejects call_screening_policy on encrypted contacts" do
      contact = Contact.new(
        addressbook: addressbook,
        uri: "enc-pol.vcf",
        uid: "enc-pol",
        encrypted: true,
        vcard_data: Base64.strict_encode64("ciphertext"),
        etag: "\"e\"",
        call_screening_policy: "block"
      )
      expect(contact).not_to be_valid
      expect(contact.errors[:call_screening_policy]).to include(/encrypted contacts/)
    end

    it "allows nil policy on encrypted contacts" do
      contact = Contact.new(
        addressbook: addressbook,
        uri: "enc-ok.vcf",
        uid: "enc-ok",
        encrypted: true,
        vcard_data: Base64.strict_encode64("ciphertext"),
        etag: "\"e\"",
        call_screening_policy: nil
      )
      expect(contact).to be_valid
    end
  end

  describe "#effective_screening_policy" do
    it "returns own policy when set" do
      ab = create(:addressbook, user: user, call_screening_policy: "screen")
      contact = Contact.create!(
        addressbook: ab,
        uri: "p.vcf",
        vcard_data: "BEGIN:VCARD\r\nVERSION:3.0\r\nUID:p\r\nFN:P\r\nEND:VCARD\r\n",
        call_screening_policy: "block"
      )
      expect(contact.effective_screening_policy).to eq("block")
    end

    it "inherits from addressbook when own policy is nil" do
      ab = create(:addressbook, user: user, call_screening_policy: "allow")
      contact = Contact.create!(
        addressbook: ab,
        uri: "p2.vcf",
        vcard_data: "BEGIN:VCARD\r\nVERSION:3.0\r\nUID:p2\r\nFN:P2\r\nEND:VCARD\r\n"
      )
      expect(contact.effective_screening_policy).to eq("allow")
    end
  end
end
