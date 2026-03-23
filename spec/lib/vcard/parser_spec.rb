require "rails_helper"

RSpec.describe Vcard::Parser do
  describe ".extract_categories" do
    it "parses simple CATEGORIES" do
      vcard = "BEGIN:VCARD\r\nVERSION:3.0\r\nUID:uid1\r\nFN:Test\r\nCATEGORIES:Family,Work\r\nEND:VCARD\r\n"
      result = described_class.parse(vcard)
      expect(result.categories).to eq(["Family", "Work"])
    end

    it "handles escaped commas" do
      vcard = "BEGIN:VCARD\r\nVERSION:3.0\r\nUID:uid1\r\nFN:Test\r\nCATEGORIES:Family\\, Extended,Friends\r\nEND:VCARD\r\n"
      result = described_class.parse(vcard)
      expect(result.categories).to eq(["Family, Extended", "Friends"])
    end

    it "merges multiple CATEGORIES lines" do
      vcard = "BEGIN:VCARD\r\nVERSION:3.0\r\nUID:uid1\r\nFN:Test\r\nCATEGORIES:Family\r\nCATEGORIES:Work\r\nEND:VCARD\r\n"
      result = described_class.parse(vcard)
      expect(result.categories).to match_array(["Family", "Work"])
    end

    it "returns empty array when no CATEGORIES" do
      vcard = "BEGIN:VCARD\r\nVERSION:3.0\r\nUID:uid1\r\nFN:Test\r\nEND:VCARD\r\n"
      result = described_class.parse(vcard)
      expect(result.categories).to eq([])
    end

    it "deduplicates categories" do
      vcard = "BEGIN:VCARD\r\nVERSION:3.0\r\nUID:uid1\r\nFN:Test\r\nCATEGORIES:Family,Family\r\nEND:VCARD\r\n"
      result = described_class.parse(vcard)
      expect(result.categories).to eq(["Family"])
    end
  end

  describe ".extract_kind" do
    it "returns group for KIND:group" do
      vcard = "BEGIN:VCARD\r\nVERSION:3.0\r\nUID:uid1\r\nKIND:group\r\nFN:Team\r\nEND:VCARD\r\n"
      result = described_class.parse(vcard)
      expect(result.kind).to eq("group")
    end

    it "returns individual for KIND:individual" do
      vcard = "BEGIN:VCARD\r\nVERSION:3.0\r\nUID:uid1\r\nKIND:individual\r\nFN:Test\r\nEND:VCARD\r\n"
      result = described_class.parse(vcard)
      expect(result.kind).to eq("individual")
    end

    it "falls back to X-ADDRESSBOOKSERVER-KIND" do
      vcard = "BEGIN:VCARD\r\nVERSION:3.0\r\nUID:uid1\r\nX-ADDRESSBOOKSERVER-KIND:group\r\nFN:Team\r\nEND:VCARD\r\n"
      result = described_class.parse(vcard)
      expect(result.kind).to eq("group")
    end

    it "defaults to individual when no KIND property" do
      vcard = "BEGIN:VCARD\r\nVERSION:3.0\r\nUID:uid1\r\nFN:Test\r\nEND:VCARD\r\n"
      result = described_class.parse(vcard)
      expect(result.kind).to eq("individual")
    end
  end

  describe ".extract_member_uids" do
    it "parses MEMBER:urn:uuid:..." do
      vcard = "BEGIN:VCARD\r\nVERSION:3.0\r\nUID:uid1\r\nKIND:group\r\nFN:Team\r\nMEMBER:urn:uuid:abc-123\r\nMEMBER:urn:uuid:def-456\r\nEND:VCARD\r\n"
      result = described_class.parse(vcard)
      expect(result.member_uids).to eq(["abc-123", "def-456"])
    end

    it "parses X-ADDRESSBOOKSERVER-MEMBER" do
      vcard = "BEGIN:VCARD\r\nVERSION:3.0\r\nUID:uid1\r\nX-ADDRESSBOOKSERVER-KIND:group\r\nFN:Team\r\nX-ADDRESSBOOKSERVER-MEMBER:urn:uuid:abc-123\r\nEND:VCARD\r\n"
      result = described_class.parse(vcard)
      expect(result.member_uids).to eq(["abc-123"])
    end

    it "returns empty array when no MEMBER properties" do
      vcard = "BEGIN:VCARD\r\nVERSION:3.0\r\nUID:uid1\r\nFN:Test\r\nEND:VCARD\r\n"
      result = described_class.parse(vcard)
      expect(result.member_uids).to eq([])
    end
  end

  describe ".update_categories" do
    let(:vcard) { "BEGIN:VCARD\r\nVERSION:3.0\r\nUID:uid1\r\nFN:Test\r\nEND:VCARD\r\n" }

    it "adds CATEGORIES line to vCard without categories" do
      result = described_class.update_categories(vcard, ["Family", "Work"])
      expect(result).to include("CATEGORIES:Family,Work")
      expect(result).to include("END:VCARD")
    end

    it "replaces existing CATEGORIES" do
      vcard_with = "BEGIN:VCARD\r\nVERSION:3.0\r\nUID:uid1\r\nFN:Test\r\nCATEGORIES:Old\r\nEND:VCARD\r\n"
      result = described_class.update_categories(vcard_with, ["New"])
      expect(result).to include("CATEGORIES:New")
      expect(result).not_to include("CATEGORIES:Old")
    end

    it "removes CATEGORIES when empty array" do
      vcard_with = "BEGIN:VCARD\r\nVERSION:3.0\r\nUID:uid1\r\nFN:Test\r\nCATEGORIES:Family\r\nEND:VCARD\r\n"
      result = described_class.update_categories(vcard_with, [])
      expect(result).not_to include("CATEGORIES")
    end

    it "escapes commas in category names" do
      result = described_class.update_categories(vcard, ["Family, Extended", "Work"])
      expect(result).to include("CATEGORIES:Family\\, Extended,Work")
    end

    it "preserves other vCard properties" do
      vcard_full = "BEGIN:VCARD\r\nVERSION:3.0\r\nUID:uid1\r\nFN:Test\r\nEMAIL:test@test.com\r\nTEL:555-1234\r\nEND:VCARD\r\n"
      result = described_class.update_categories(vcard_full, ["Work"])
      expect(result).to include("EMAIL:test@test.com")
      expect(result).to include("TEL:555-1234")
      expect(result).to include("CATEGORIES:Work")
    end
  end

  describe ".update_members" do
    let(:vcard) { "BEGIN:VCARD\r\nVERSION:3.0\r\nUID:uid1\r\nKIND:group\r\nFN:Team\r\nEND:VCARD\r\n" }

    it "adds MEMBER lines" do
      result = described_class.update_members(vcard, ["abc-123", "def-456"])
      expect(result).to include("MEMBER:urn:uuid:abc-123")
      expect(result).to include("MEMBER:urn:uuid:def-456")
    end

    it "replaces existing MEMBER lines" do
      vcard_with = "BEGIN:VCARD\r\nVERSION:3.0\r\nUID:uid1\r\nKIND:group\r\nFN:Team\r\nMEMBER:urn:uuid:old-uid\r\nEND:VCARD\r\n"
      result = described_class.update_members(vcard_with, ["new-uid"])
      expect(result).to include("MEMBER:urn:uuid:new-uid")
      expect(result).not_to include("old-uid")
    end

    it "removes MEMBER lines when empty array" do
      vcard_with = "BEGIN:VCARD\r\nVERSION:3.0\r\nUID:uid1\r\nKIND:group\r\nFN:Team\r\nMEMBER:urn:uuid:old-uid\r\nEND:VCARD\r\n"
      result = described_class.update_members(vcard_with, [])
      expect(result).not_to include("MEMBER")
    end
  end

  describe ".generate with categories" do
    it "includes CATEGORIES line" do
      result = described_class.generate(first_name: "Test", categories: ["Family", "Work"])
      expect(result).to include("CATEGORIES:Family,Work")
    end

    it "escapes commas in categories" do
      result = described_class.generate(first_name: "Test", categories: ["Family, Extended"])
      expect(result).to include("CATEGORIES:Family\\, Extended")
    end

    it "omits CATEGORIES when empty" do
      result = described_class.generate(first_name: "Test", categories: [])
      expect(result).not_to include("CATEGORIES")
    end
  end

  describe ".generate with kind:group" do
    it "creates KIND:group vCard" do
      result = described_class.generate(kind: "group", full_name: "Team", member_uids: ["uid-1", "uid-2"])
      expect(result).to include("KIND:group")
      expect(result).to include("FN:Team")
      expect(result).to include("MEMBER:urn:uuid:uid-1")
      expect(result).to include("MEMBER:urn:uuid:uid-2")
      expect(result).not_to include("EMAIL")
    end
  end
end
