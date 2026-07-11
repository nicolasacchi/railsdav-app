require "rails_helper"

# Regression coverage for the share-permission enforcement fix: read-only and
# pending-share guests must not be able to create/update/delete contacts, even
# by hitting the routes directly (the write UI is merely hidden, not enforcing).
RSpec.describe "Contacts write permission", type: :request do
  let(:owner) { create(:user, username: "owner") }
  let(:guest) { create(:user, username: "guest", password: "password123") }
  let(:book)  { create(:addressbook, user: owner, uri: "shared") }
  let!(:contact) do
    create(:contact, addressbook: book, uri: "c1.vcf",
           vcard_data: "BEGIN:VCARD\r\nVERSION:3.0\r\nUID:c1\r\nFN:Existing\r\nEND:VCARD\r\n")
  end

  def login(user)
    post login_path, params: { email: user.email, password: "password123" }
  end

  context "read-only accepted share" do
    before do
      create(:addressbook_share, addressbook: book, user: guest, permission: "read", status: "accepted")
      login(guest)
    end

    it "forbids creating a contact" do
      expect {
        post addressbook_contacts_path(book.uri), params: { raw_vcard: "BEGIN:VCARD\r\nVERSION:3.0\r\nUID:x\r\nFN:X\r\nEND:VCARD\r\n" }
      }.not_to change(book.contacts, :count)
      expect(response).to redirect_to(all_contacts_path)
    end

    it "forbids updating a contact" do
      patch addressbook_contact_path(book.uri, contact.uri), params: { raw_vcard: "BEGIN:VCARD\r\nVERSION:3.0\r\nUID:c1\r\nFN:Hacked\r\nEND:VCARD\r\n" }
      expect(response).to redirect_to(all_contacts_path)
      expect(contact.reload.vcard_data).to include("FN:Existing")
    end

    it "forbids deleting a contact" do
      expect {
        delete addressbook_contact_path(book.uri, contact.uri)
      }.not_to change(book.contacts, :count)
      expect(response).to redirect_to(all_contacts_path)
    end
  end

  context "write-enabled accepted share" do
    before do
      create(:addressbook_share, addressbook: book, user: guest, permission: "write", status: "accepted")
      login(guest)
    end

    it "allows updating a contact" do
      patch addressbook_contact_path(book.uri, contact.uri), params: { raw_vcard: "BEGIN:VCARD\r\nVERSION:3.0\r\nUID:c1\r\nFN:Edited\r\nEND:VCARD\r\n" }
      expect(contact.reload.vcard_data).to include("FN:Edited")
    end
  end

  context "pending (unaccepted) share" do
    before do
      create(:addressbook_share, :pending, addressbook: book, user: guest, permission: "write")
      login(guest)
    end

    it "cannot even reach the book (not found)" do
      get addressbook_contacts_path(book.uri) rescue nil
      delete addressbook_contact_path(book.uri, contact.uri)
      # The pending share does not resolve the book, so the contact is untouched.
      expect(contact.reload.vcard_data).to include("FN:Existing")
    end
  end
end
