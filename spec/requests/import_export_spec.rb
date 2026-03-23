require "rails_helper"

RSpec.describe "Import/Export", type: :request do
  let!(:user) { create(:user, username: "alice", password: "password123") }
  let!(:addressbook) { user.addressbooks.first || create(:addressbook, user: user, uri: "contacts") }
  let(:vcard_data) { "BEGIN:VCARD\r\nVERSION:3.0\r\nUID:test-uid\r\nFN:Test User\r\nN:User;Test;;;\r\nEMAIL:test@example.com\r\nEND:VCARD\r\n" }
  let!(:contact) { create(:contact, addressbook: addressbook, uid: "test-uid", uri: "test.vcf", vcard_data: vcard_data) }

  def login_as(user)
    post login_path, params: { email: user.email, password: "password123" }
    follow_redirect!
  end

  describe "Addressbook export" do
    before { login_as(user) }

    it "exports as vCard" do
      get export_addressbook_path(addressbook.uri, export_format: "vcf")
      expect(response).to have_http_status(200)
      expect(response.content_type).to include("text/vcard")
      expect(response.body).to include("BEGIN:VCARD")
      expect(response.body).to include("FN:Test User")
    end

    it "exports as CSV" do
      get export_addressbook_path(addressbook.uri, export_format: "csv")
      expect(response).to have_http_status(200)
      expect(response.content_type).to include("text/csv")
      expect(response.body).to include("full_name")
      expect(response.body).to include("Test User")
    end

    it "exports as JSON" do
      get export_addressbook_path(addressbook.uri, export_format: "json")
      expect(response).to have_http_status(200)
      expect(response.content_type).to include("application/json")
      data = JSON.parse(response.body)
      expect(data.first["full_name"]).to eq("Test User")
    end

    it "redirects for unknown format" do
      get export_addressbook_path(addressbook.uri, export_format: "xml")
      expect(response).to redirect_to(addressbook_path(addressbook.uri))
    end

    it "requires authentication" do
      delete logout_path
      get export_addressbook_path(addressbook.uri, export_format: "vcf")
      expect(response).to redirect_to(login_path)
    end
  end

  describe "Contact export" do
    before { login_as(user) }

    it "exports individual contact as vCard" do
      get export_addressbook_contact_path(addressbook.uri, contact.uri, export_format: "vcf")
      expect(response).to have_http_status(200)
      expect(response.content_type).to include("text/vcard")
      expect(response.body).to include("FN:Test User")
    end

    it "exports individual contact as CSV" do
      get export_addressbook_contact_path(addressbook.uri, contact.uri, export_format: "csv")
      expect(response).to have_http_status(200)
      expect(response.content_type).to include("text/csv")
    end

    it "exports individual contact as JSON" do
      get export_addressbook_contact_path(addressbook.uri, contact.uri, export_format: "json")
      expect(response).to have_http_status(200)
      expect(response.content_type).to include("application/json")
    end
  end

  describe "Import" do
    before { login_as(user) }

    it "imports a vcf file" do
      vcf = "BEGIN:VCARD\r\nVERSION:3.0\r\nUID:new-uid\r\nFN:New Contact\r\nN:Contact;New;;;\r\nEND:VCARD\r\n"
      file = Rack::Test::UploadedFile.new(StringIO.new(vcf), "text/vcard", original_filename: "import.vcf")

      expect {
        post import_addressbook_path(addressbook.uri), params: { file: file }
      }.to change { addressbook.contacts.count }.by(1)

      expect(response).to redirect_to(addressbook_path(addressbook.uri))
      follow_redirect!
      expect(response.body).to include("Imported 1 new")
    end

    it "imports a csv file" do
      csv = "uid,full_name,email_1\ncsv-uid,CSV Contact,csv@example.com\n"
      file = Rack::Test::UploadedFile.new(StringIO.new(csv), "text/csv", original_filename: "import.csv")

      expect {
        post import_addressbook_path(addressbook.uri), params: { file: file }
      }.to change { addressbook.contacts.count }.by(1)
    end

    it "imports a json file" do
      json = JSON.generate([{ uid: "json-uid", full_name: "JSON Contact", emails: ["j@example.com"] }])
      file = Rack::Test::UploadedFile.new(StringIO.new(json), "application/json", original_filename: "import.json")

      expect {
        post import_addressbook_path(addressbook.uri), params: { file: file }
      }.to change { addressbook.contacts.count }.by(1)
    end

    it "overwrites duplicates by UID" do
      vcf = "BEGIN:VCARD\r\nVERSION:3.0\r\nUID:test-uid\r\nFN:Updated Name\r\nN:Name;Updated;;;\r\nEND:VCARD\r\n"
      file = Rack::Test::UploadedFile.new(StringIO.new(vcf), "text/vcard", original_filename: "import.vcf")

      expect {
        post import_addressbook_path(addressbook.uri), params: { file: file }
      }.not_to change { addressbook.contacts.count }

      expect(contact.reload.vcard_data).to include("FN:Updated Name")
      follow_redirect!
      expect(response.body).to include("updated 1 existing")
    end

    it "creates SyncChange records" do
      vcf = "BEGIN:VCARD\r\nVERSION:3.0\r\nUID:sync-uid\r\nFN:Sync Test\r\nN:Test;Sync;;;\r\nEND:VCARD\r\n"
      file = Rack::Test::UploadedFile.new(StringIO.new(vcf), "text/vcard", original_filename: "import.vcf")

      expect {
        post import_addressbook_path(addressbook.uri), params: { file: file }
      }.to change { addressbook.sync_changes.count }.by(1)
    end

    it "shows error for no file" do
      post import_addressbook_path(addressbook.uri)
      expect(response).to redirect_to(addressbook_path(addressbook.uri))
      follow_redirect!
      expect(response.body).to include("Please select a file")
    end

    it "shows error for unsupported format" do
      file = Rack::Test::UploadedFile.new(StringIO.new("data"), "text/plain", original_filename: "bad.txt")
      post import_addressbook_path(addressbook.uri), params: { file: file }
      expect(response).to redirect_to(addressbook_path(addressbook.uri))
      follow_redirect!
      expect(response.body).to include("Unsupported file format")
    end

    it "requires authentication" do
      delete logout_path
      post import_addressbook_path(addressbook.uri)
      expect(response).to redirect_to(login_path)
    end
  end
end
