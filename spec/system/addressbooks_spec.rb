require "rails_helper"

RSpec.describe "Addressbooks", type: :system do
  let!(:user) { create(:user, username: "alice", email: "alice@example.com", password: "password123") }

  before do
    visit login_path
    fill_in "Email", with: "alice@example.com"
    fill_in "Password", with: "password123"
    click_button "Log In"
  end

  it "shows the addressbooks page with default addressbook" do
    visit addressbooks_path
    expect(page).to have_content("Address Books")
    expect(page).to have_content("Contacts")
    expect(page).to have_content("0 contacts")
  end

  it "shows CardDAV connection details" do
    visit addressbooks_path
    expect(page).to have_content("CardDAV Connection")
    expect(page).to have_content("alice@example.com")
    expect(page).to have_content("/dav/alice/contacts/")
  end

  it "creates a new addressbook" do
    visit addressbooks_path
    click_link "New Addressbook"

    fill_in "URI", with: "work"
    fill_in "Display Name", with: "Work Contacts"
    click_button "Create"

    expect(page).to have_content("Addressbook created")
    visit addressbooks_path
    expect(page).to have_content("Work Contacts")
  end

  it "shows addressbook detail page" do
    ab = user.addressbooks.find_by(uri: "default")
    ab.contacts.create!(
      uri: "test.vcf",
      vcard_data: "BEGIN:VCARD\r\nVERSION:3.0\r\nUID:test\r\nFN:Test User\r\nEND:VCARD\r\n"
    )

    visit addressbook_path("default")
    expect(page).to have_content("Test User")
  end
end
