require "rails_helper"

RSpec.describe ContactPhoneNumber, type: :model do
  let(:addressbook) { create(:addressbook) }

  def contact_with_phones(*phones)
    tel_lines = phones.map { |p| "TEL:#{p}" }.join("\r\n")
    vcard = "BEGIN:VCARD\r\nVERSION:3.0\r\nUID:uid-#{SecureRandom.hex(4)}\r\nFN:Phone Owner\r\n#{tel_lines}\r\nEND:VCARD\r\n"
    create(:contact, addressbook: addressbook, uri: "#{SecureRandom.uuid}.vcf", vcard_data: vcard)
  end

  it "is derived from a contact's TEL properties and normalized to E.164" do
    contact = contact_with_phones("+39 333 1234567")
    expect(contact.contact_phone_numbers.pluck(:e164)).to eq(["+393331234567"])
  end

  it "rebuilds the index when the vCard changes" do
    contact = contact_with_phones("+393331234567")
    contact.update!(vcard_data: contact.vcard_data.sub("+393331234567", "+393339999999"))
    expect(contact.contact_phone_numbers.reload.pluck(:e164)).to eq(["+393339999999"])
  end

  it "deduplicates numbers that normalize to the same E.164" do
    contact = contact_with_phones("+393331234567", "0039 333 1234567")
    expect(contact.contact_phone_numbers.count).to eq(1)
  end

  it "is removed when the contact is destroyed" do
    contact = contact_with_phones("+393331234567")
    expect { contact.destroy }.to change(ContactPhoneNumber, :count).by(-1)
  end

  it "skips invalid phone values" do
    contact = contact_with_phones("not-a-phone")
    expect(contact.contact_phone_numbers).to be_empty
  end
end
