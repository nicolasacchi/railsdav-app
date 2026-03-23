require "rails_helper"

RSpec.describe "Contacts", type: :system do
  let!(:user) { create(:user, username: "alice", email: "alice@example.com", password: "password123") }
  let(:addressbook) { user.addressbooks.find_by(uri: "default") }

  before do
    visit login_path
    fill_in "Email", with: "alice@example.com"
    fill_in "Password", with: "password123"
    click_button "Log In"
  end

  describe "Contacts list" do
    it "shows empty state when no contacts" do
      visit all_contacts_path
      expect(page).to have_content("Contacts (0)")
      expect(page).to have_content("No contacts yet")
    end

    it "shows contacts when they exist" do
      addressbook.contacts.create!(
        uri: "test.vcf",
        vcard_data: "BEGIN:VCARD\r\nVERSION:3.0\r\nUID:test-1\r\nFN:Alice Smith\r\nEMAIL:alice@smith.com\r\nEND:VCARD\r\n"
      )

      visit all_contacts_path
      expect(page).to have_content("Contacts (1)")
      expect(page).to have_content("Alice Smith")
      expect(page).to have_content("alice@smith.com")
    end

    it "handles vCards with scrubbed content without crashing" do
      # Simulate a vCard that went through scrub (as would happen in production after the fix)
      bad_vcard = "BEGIN:VCARD\r\nVERSION:3.0\r\nUID:bad-1\r\nFN:Bad Contact\r\nPHOTO;ENCODING=b:binary-data-here\r\nEND:VCARD\r\n"
      addressbook.contacts.create!(uri: "bad.vcf", vcard_data: bad_vcard)

      visit all_contacts_path
      expect(page).to have_content("Contacts (1)")
      expect(page).to have_content("Bad Contact")
    end
  end

  describe "Create contact" do
    it "creates a contact via form" do
      visit all_contacts_path
      click_link "+ New"

      fill_in "First Name", with: "John"
      fill_in "Last Name", with: "Doe"
      fill_in "Email", with: "john@example.com"
      fill_in "Phone", with: "+1-555-0100"
      click_button "Create Contact"

      expect(page).to have_content("Contact created")
      expect(page).to have_content("John Doe")
      expect(page).to have_content("john@example.com")
      expect(page).to have_content("+1-555-0100")
    end
  end

  describe "View contact" do
    it "shows contact details" do
      addressbook.contacts.create!(
        uri: "jane.vcf",
        vcard_data: "BEGIN:VCARD\r\nVERSION:3.0\r\nUID:jane-1\r\nFN:Jane Doe\r\nEMAIL:jane@example.com\r\nTEL:+1-555-0200\r\nORG:Acme Corp\r\nEND:VCARD\r\n"
      )

      visit addressbook_contact_path("default", "jane.vcf")
      expect(page).to have_content("Jane Doe")
      expect(page).to have_content("jane@example.com")
      expect(page).to have_content("+1-555-0200")
      expect(page).to have_content("Acme Corp")
    end
  end

  describe "Delete contact" do
    it "deletes a contact" do
      contact = addressbook.contacts.create!(
        uri: "del.vcf",
        vcard_data: "BEGIN:VCARD\r\nVERSION:3.0\r\nUID:del-1\r\nFN:Delete Me\r\nEND:VCARD\r\n"
      )

      # Use direct request since delete requires JS confirmation
      page.driver.submit :delete, addressbook_contact_path("default", "del.vcf"), {}
      expect(page).to have_content("Contact deleted")
    end
  end
end
