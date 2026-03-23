require "rails_helper"

RSpec.describe Contacts::Exporter do
  let(:addressbook) { create(:addressbook) }

  let(:vcard1) do
    "BEGIN:VCARD\r\nVERSION:3.0\r\nUID:uid-1\r\nFN:Alice Smith\r\nN:Smith;Alice;;;\r\nEMAIL:alice@example.com\r\nTEL:555-0001\r\nORG:Acme Corp\r\nTITLE:Engineer\r\nNOTE:A note\r\nEND:VCARD\r\n"
  end

  let(:vcard2) do
    "BEGIN:VCARD\r\nVERSION:3.0\r\nUID:uid-2\r\nFN:Bob Jones\r\nN:Jones;Bob;;;\r\nEMAIL:bob@example.com\r\nEMAIL:bob2@example.com\r\nTEL:555-0002\r\nTEL:555-0003\r\nEND:VCARD\r\n"
  end

  let!(:contact1) { create(:contact, addressbook: addressbook, uid: "uid-1", uri: "c1.vcf", vcard_data: vcard1) }
  let!(:contact2) { create(:contact, addressbook: addressbook, uid: "uid-2", uri: "c2.vcf", vcard_data: vcard2) }

  let(:contacts) { addressbook.contacts.order(:uri) }

  describe ".to_vcf" do
    it "concatenates vcard_data from all contacts" do
      result = described_class.to_vcf(contacts)
      expect(result).to include("UID:uid-1")
      expect(result).to include("UID:uid-2")
      expect(result.scan("BEGIN:VCARD").count).to eq(2)
    end

    it "handles empty collection" do
      expect(described_class.to_vcf(Contact.none)).to eq("")
    end
  end

  describe ".to_csv" do
    it "produces CSV with correct headers" do
      result = described_class.to_csv(contacts)
      csv = CSV.parse(result.sub("\xEF\xBB\xBF", ""), headers: true)
      expect(csv.headers).to eq(%w[uid full_name first_name last_name email_1 email_2 email_3 phone_1 phone_2 phone_3 organization title note categories])
    end

    it "maps contact fields correctly" do
      result = described_class.to_csv(contacts)
      csv = CSV.parse(result.sub("\xEF\xBB\xBF", ""), headers: true)
      row = csv.find { |r| r["uid"] == "uid-1" }
      expect(row["full_name"]).to eq("Alice Smith")
      expect(row["first_name"]).to eq("Alice")
      expect(row["last_name"]).to eq("Smith")
      expect(row["email_1"]).to eq("alice@example.com")
      expect(row["phone_1"]).to eq("555-0001")
      expect(row["organization"]).to eq("Acme Corp")
      expect(row["title"]).to eq("Engineer")
      expect(row["note"]).to eq("A note")
    end

    it "maps multiple emails and phones to numbered columns" do
      result = described_class.to_csv(contacts)
      csv = CSV.parse(result.sub("\xEF\xBB\xBF", ""), headers: true)
      row = csv.find { |r| r["uid"] == "uid-2" }
      expect(row["email_1"]).to eq("bob@example.com")
      expect(row["email_2"]).to eq("bob2@example.com")
      expect(row["phone_1"]).to eq("555-0002")
      expect(row["phone_2"]).to eq("555-0003")
    end

    it "includes BOM for Excel compatibility" do
      result = described_class.to_csv(contacts)
      expect(result.bytes[0..2]).to eq([0xEF, 0xBB, 0xBF])
    end

    it "handles empty collection" do
      result = described_class.to_csv(Contact.none)
      csv = CSV.parse(result.sub("\xEF\xBB\xBF", ""), headers: true)
      expect(csv.size).to eq(0)
    end
  end

  describe ".to_json" do
    it "produces valid JSON array" do
      result = described_class.to_json(contacts)
      data = JSON.parse(result)
      expect(data).to be_an(Array)
      expect(data.size).to eq(2)
    end

    it "includes all expected fields" do
      result = described_class.to_json(contacts)
      data = JSON.parse(result)
      alice = data.find { |c| c["uid"] == "uid-1" }
      expect(alice["full_name"]).to eq("Alice Smith")
      expect(alice["first_name"]).to eq("Alice")
      expect(alice["last_name"]).to eq("Smith")
      expect(alice["emails"]).to eq(["alice@example.com"])
      expect(alice["phones"]).to eq(["555-0001"])
      expect(alice["organization"]).to eq("Acme Corp")
      expect(alice["title"]).to eq("Engineer")
      expect(alice["note"]).to eq("A note")
      expect(alice["addresses"]).to be_an(Array)
    end

    it "handles multiple emails and phones" do
      result = described_class.to_json(contacts)
      data = JSON.parse(result)
      bob = data.find { |c| c["uid"] == "uid-2" }
      expect(bob["emails"]).to eq(["bob@example.com", "bob2@example.com"])
      expect(bob["phones"]).to eq(["555-0002", "555-0003"])
    end

    it "handles empty collection" do
      result = described_class.to_json(Contact.none)
      expect(JSON.parse(result)).to eq([])
    end
  end

  describe "categories support" do
    let(:vcard_with_categories) do
      "BEGIN:VCARD\r\nVERSION:3.0\r\nUID:uid-cat\r\nFN:Cat User\r\nN:User;Cat;;;\r\nCATEGORIES:Family,Work\r\nEND:VCARD\r\n"
    end
    let!(:contact_with_cats) { create(:contact, addressbook: addressbook, uid: "uid-cat", uri: "cat.vcf", vcard_data: vcard_with_categories) }

    it "exports categories in CSV" do
      result = described_class.to_csv([contact_with_cats])
      csv = CSV.parse(result.sub("\xEF\xBB\xBF", ""), headers: true)
      row = csv.first
      expect(row["categories"]).to eq("Family, Work")
    end

    it "exports categories in JSON" do
      result = described_class.to_json([contact_with_cats])
      data = JSON.parse(result)
      expect(data.first["categories"]).to eq(["Family", "Work"])
    end
  end

  describe "KIND:group exclusion" do
    let(:group_vcard) do
      "BEGIN:VCARD\r\nVERSION:3.0\r\nUID:grp-uid\r\nKIND:group\r\nFN:GroupCard\r\nN:GroupCard;;;;\r\nEND:VCARD\r\n"
    end
    let!(:group_contact) { create(:contact, addressbook: addressbook, uid: "grp-uid", uri: "grp.vcf", vcard_data: group_vcard) }

    it "excludes KIND:group from VCF export" do
      result = described_class.to_vcf(contacts)
      expect(result).not_to include("KIND:group")
      expect(result).not_to include("GroupCard")
    end

    it "excludes KIND:group from CSV export" do
      result = described_class.to_csv(contacts)
      csv = CSV.parse(result.sub("\xEF\xBB\xBF", ""), headers: true)
      uids = csv.map { |r| r["uid"] }
      expect(uids).not_to include("grp-uid")
    end

    it "excludes KIND:group from JSON export" do
      result = described_class.to_json(contacts)
      data = JSON.parse(result)
      uids = data.map { |c| c["uid"] }
      expect(uids).not_to include("grp-uid")
    end
  end
end
