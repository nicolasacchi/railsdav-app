require "rails_helper"

RSpec.describe Contacts::Importer do
  let(:user) { create(:user) }
  let(:addressbook) { create(:addressbook, user: user) }

  def make_file(content, filename)
    file = StringIO.new(content)
    file.define_singleton_method(:original_filename) { filename }
    file
  end

  describe "vCard import" do
    let(:vcf_content) do
      "BEGIN:VCARD\r\nVERSION:3.0\r\nUID:import-1\r\nFN:Alice\r\nN:;Alice;;;\r\nEND:VCARD\r\n" \
      "\r\n" \
      "BEGIN:VCARD\r\nVERSION:3.0\r\nUID:import-2\r\nFN:Bob\r\nN:;Bob;;;\r\nEND:VCARD\r\n"
    end

    it "imports multiple contacts from a vcf file" do
      result = described_class.new(addressbook: addressbook, file: make_file(vcf_content, "contacts.vcf"), filename: "contacts.vcf").call
      expect(result.imported).to eq(2)
      expect(result.updated).to eq(0)
      expect(result.failed).to eq(0)
      expect(addressbook.contacts.count).to eq(2)
    end

    it "creates SyncChange records" do
      described_class.new(addressbook: addressbook, file: make_file(vcf_content, "contacts.vcf"), filename: "contacts.vcf").call
      expect(addressbook.sync_changes.where(change_type: "created").count).to eq(2)
    end

    it "increments sync_token" do
      expect {
        described_class.new(addressbook: addressbook, file: make_file(vcf_content, "contacts.vcf"), filename: "contacts.vcf").call
      }.to change { addressbook.reload.sync_token }.by(1)
    end

    it "overwrites duplicate by UID" do
      create(:contact, addressbook: addressbook, uid: "import-1", uri: "existing.vcf",
        vcard_data: "BEGIN:VCARD\r\nVERSION:3.0\r\nUID:import-1\r\nFN:Old Name\r\nN:;Old;;;\r\nEND:VCARD\r\n")

      result = described_class.new(addressbook: addressbook, file: make_file(vcf_content, "contacts.vcf"), filename: "contacts.vcf").call
      expect(result.imported).to eq(1)
      expect(result.updated).to eq(1)
      expect(addressbook.contacts.find_by(uid: "import-1").vcard_data).to include("FN:Alice")
    end
  end

  describe "CSV import" do
    let(:csv_content) do
      "uid,full_name,first_name,last_name,email_1,phone_1,organization,title,note\n" \
      "csv-1,Alice Smith,Alice,Smith,alice@example.com,555-0001,Acme,Engineer,A note\n" \
      "csv-2,Bob Jones,Bob,Jones,bob@example.com,555-0002,,,"
    end

    it "imports contacts from CSV" do
      result = described_class.new(addressbook: addressbook, file: make_file(csv_content, "contacts.csv"), filename: "contacts.csv").call
      expect(result.imported).to eq(2)
      expect(addressbook.contacts.count).to eq(2)
    end

    it "maps CSV fields to vCard data" do
      described_class.new(addressbook: addressbook, file: make_file(csv_content, "contacts.csv"), filename: "contacts.csv").call
      contact = addressbook.contacts.find_by(uid: "csv-1")
      expect(contact.vcard_data).to include("FN:Alice Smith")
      expect(contact.vcard_data).to include("EMAIL:alice@example.com")
      expect(contact.vcard_data).to include("ORG:Acme")
    end

    it "accepts aliased headers" do
      csv = "name,email,phone,company\nAlice,alice@ex.com,555,,\n"
      result = described_class.new(addressbook: addressbook, file: make_file(csv, "test.csv"), filename: "test.csv").call
      expect(result.imported).to eq(1)
    end

    it "skips rows with no name" do
      csv = "full_name,email_1\n,alice@example.com\nBob,bob@example.com\n"
      result = described_class.new(addressbook: addressbook, file: make_file(csv, "test.csv"), filename: "test.csv").call
      expect(result.imported).to eq(1)
    end
  end

  describe "JSON import" do
    let(:json_content) do
      JSON.generate([
        { uid: "json-1", full_name: "Alice Smith", first_name: "Alice", last_name: "Smith", emails: ["alice@example.com"], phones: ["555-0001"], organization: "Acme" },
        { uid: "json-2", full_name: "Bob Jones", emails: ["bob@example.com"] }
      ])
    end

    it "imports contacts from JSON" do
      result = described_class.new(addressbook: addressbook, file: make_file(json_content, "contacts.json"), filename: "contacts.json").call
      expect(result.imported).to eq(2)
      expect(addressbook.contacts.count).to eq(2)
    end

    it "maps JSON fields to vCard data" do
      described_class.new(addressbook: addressbook, file: make_file(json_content, "contacts.json"), filename: "contacts.json").call
      contact = addressbook.contacts.find_by(uid: "json-1")
      expect(contact.vcard_data).to include("FN:Alice Smith")
      expect(contact.vcard_data).to include("ORG:Acme")
    end
  end

  describe "CSV import with categories" do
    let(:csv_with_cats) do
      "full_name,email_1,categories\nAlice,alice@ex.com,\"Family, Work\"\n"
    end

    it "includes CATEGORIES in generated vCard" do
      result = described_class.new(addressbook: addressbook, file: make_file(csv_with_cats, "cats.csv"), filename: "cats.csv").call
      expect(result.imported).to eq(1)
      contact = addressbook.contacts.last
      parsed = Vcard::Parser.parse(contact.vcard_data)
      expect(parsed.categories).to match_array(["Family", "Work"])
    end
  end

  describe "JSON import with categories" do
    let(:json_with_cats) do
      JSON.generate([
        { full_name: "Alice", emails: ["alice@ex.com"], categories: ["Family", "Work"] }
      ])
    end

    it "includes CATEGORIES in generated vCard" do
      result = described_class.new(addressbook: addressbook, file: make_file(json_with_cats, "cats.json"), filename: "cats.json").call
      expect(result.imported).to eq(1)
      contact = addressbook.contacts.last
      parsed = Vcard::Parser.parse(contact.vcard_data)
      expect(parsed.categories).to match_array(["Family", "Work"])
    end
  end

  describe "error handling" do
    it "raises UnsupportedFormat for unknown extensions" do
      expect {
        described_class.new(addressbook: addressbook, file: make_file("data", "file.txt"), filename: "file.txt").call
      }.to raise_error(Contacts::Importer::UnsupportedFormat)
    end

    it "raises ParseError for empty vcf file" do
      expect {
        described_class.new(addressbook: addressbook, file: make_file("nothing here", "empty.vcf"), filename: "empty.vcf").call
      }.to raise_error(Contacts::Importer::ParseError, /No vCard entries/)
    end

    it "raises ParseError for malformed JSON" do
      expect {
        described_class.new(addressbook: addressbook, file: make_file("{bad", "bad.json"), filename: "bad.json").call
      }.to raise_error(Contacts::Importer::ParseError, /Invalid JSON/)
    end

    it "raises ParseError for JSON that is not an array" do
      expect {
        described_class.new(addressbook: addressbook, file: make_file('{"a":1}', "bad.json"), filename: "bad.json").call
      }.to raise_error(Contacts::Importer::ParseError, /must be an array/)
    end

    it "raises ParseError for empty CSV" do
      expect {
        described_class.new(addressbook: addressbook, file: make_file("full_name\n", "empty.csv"), filename: "empty.csv").call
      }.to raise_error(Contacts::Importer::ParseError, /no data rows/)
    end
  end
end
