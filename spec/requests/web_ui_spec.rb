require "rails_helper"

RSpec.describe "Web UI", type: :request do
  let!(:user) { create(:user, username: "alice", password: "password123") }

  def login_as(user)
    post login_path, params: { email: user.email, password: "password123" }
    follow_redirect!
  end

  describe "Login" do
    it "shows login page" do
      get login_path
      expect(response).to have_http_status(200)
      expect(response.body).to include("Log In")
    end

    it "shows landing page when not authenticated" do
      get root_path
      expect(response).to have_http_status(200)
      expect(response.body).to include("Your Contacts")
    end

    it "logs in with valid credentials" do
      post login_path, params: { email: user.email, password: "password123" }
      expect(response).to redirect_to(all_contacts_path)
    end

    it "shows error with invalid credentials" do
      post login_path, params: { email: user.email, password: "wrong" }
      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.body).to include("Invalid")
    end

    it "logs out" do
      login_as(user)
      delete logout_path
      expect(response).to redirect_to(login_path)
    end
  end

  describe "Addressbooks" do
    before { login_as(user) }

    it "lists addressbooks on dashboard" do
      get addressbooks_path
      expect(response).to have_http_status(200)
      expect(response.body).to include("Contacts")
    end

    it "shows an addressbook with its contacts" do
      ab = user.addressbooks.find_by(uri: "default")
      ab.contacts.create!(uri: "test.vcf", vcard_data: "BEGIN:VCARD\r\nVERSION:3.0\r\nUID:test\r\nFN:Test User\r\nEND:VCARD\r\n")
      get addressbook_path("default")
      expect(response).to have_http_status(200)
      expect(response.body).to include("Test User")
    end

    it "creates a new addressbook" do
      post addressbooks_path, params: { addressbook: { uri: "work", displayname: "Work Contacts", description: "Work stuff" } }
      expect(response).to redirect_to(addressbook_path("work"))
      expect(user.addressbooks.find_by(uri: "work")).to be_present
    end

    it "edits an addressbook" do
      ab = user.addressbooks.find_by(uri: "default")
      patch addressbook_path("default"), params: { addressbook: { displayname: "Personal" } }
      expect(response).to redirect_to(addressbook_path("default"))
      expect(ab.reload.displayname).to eq("Personal")
    end
  end

  describe "Contacts" do
    before { login_as(user) }

    let(:addressbook) { user.addressbooks.find_by(uri: "default") }

    it "creates a contact via form fields" do
      post addressbook_contacts_path("default"), params: {
        first_name: "John",
        last_name: "Doe",
        "emails" => ["john@example.com"],
        "phones" => ["+1-555-0100"]
      }
      expect(response).to have_http_status(302)
      contact = addressbook.contacts.last
      expect(contact).to be_present
      expect(contact.vcard_data).to include("John Doe")
      expect(contact.vcard_data).to include("john@example.com")
    end

    it "creates a contact via raw vCard" do
      raw = "BEGIN:VCARD\r\nVERSION:3.0\r\nUID:raw-test\r\nFN:Raw Contact\r\nEND:VCARD\r\n"
      post addressbook_contacts_path("default"), params: { raw_vcard: raw }
      expect(response).to have_http_status(302)
      contact = addressbook.contacts.last
      expect(contact.vcard_data).to eq(raw)
    end

    it "updates CTag and sync_token when creating via web UI" do
      expect {
        post addressbook_contacts_path("default"), params: {
          first_name: "Test", last_name: "User",
          "emails" => ["test@example.com"]
        }
      }.to change { addressbook.reload.ctag }.by(1)
        .and change { addressbook.reload.sync_token }.by(1)
    end

    it "creates sync_change when creating via web UI" do
      expect {
        post addressbook_contacts_path("default"), params: {
          first_name: "Test", last_name: "User",
          "emails" => ["test@example.com"]
        }
      }.to change(SyncChange, :count).by(1)
    end

    it "shows a contact detail page" do
      contact = addressbook.contacts.create!(
        uri: "test.vcf",
        vcard_data: "BEGIN:VCARD\r\nVERSION:3.0\r\nUID:test\r\nFN:Test User\r\nEMAIL:test@example.com\r\nEND:VCARD\r\n"
      )
      get addressbook_contact_path("default", "test.vcf")
      expect(response).to have_http_status(200)
      expect(response.body).to include("Test User")
      expect(response.body).to include("test@example.com")
    end

    it "deletes a contact and creates sync_change" do
      contact = addressbook.contacts.create!(
        uri: "test.vcf",
        vcard_data: "BEGIN:VCARD\r\nVERSION:3.0\r\nUID:test\r\nFN:Test User\r\nEND:VCARD\r\n"
      )
      addressbook.increment_sync!

      expect {
        delete addressbook_contact_path("default", "test.vcf")
      }.to change { addressbook.contacts.count }.by(-1)
        .and change { addressbook.reload.ctag }.by(1)

      sc = SyncChange.where(change_type: "deleted").last
      expect(sc.uri).to eq("test.vcf")
    end
  end
end
