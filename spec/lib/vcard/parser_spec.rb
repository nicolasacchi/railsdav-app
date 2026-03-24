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

  describe "N component extraction" do
    it "extracts all 5 N components" do
      vcard = "BEGIN:VCARD\r\nVERSION:3.0\r\nUID:uid1\r\nFN:Dr. John M. Smith Jr.\r\nN:Smith;John;Michael;Dr.;Jr.\r\nEND:VCARD\r\n"
      result = described_class.parse(vcard)
      expect(result.last_name).to eq("Smith")
      expect(result.first_name).to eq("John")
      expect(result.middle_name).to eq("Michael")
      expect(result.name_prefix).to eq("Dr.")
      expect(result.name_suffix).to eq("Jr.")
    end

    it "returns nil for missing components" do
      vcard = "BEGIN:VCARD\r\nVERSION:3.0\r\nUID:uid1\r\nFN:Jane\r\nN:;Jane;;;\r\nEND:VCARD\r\n"
      result = described_class.parse(vcard)
      expect(result.first_name).to eq("Jane")
      expect(result.middle_name).to be_nil
      expect(result.name_prefix).to be_nil
      expect(result.name_suffix).to be_nil
    end
  end

  describe "new field extraction" do
    it "extracts NICKNAME" do
      vcard = "BEGIN:VCARD\r\nVERSION:3.0\r\nUID:uid1\r\nFN:Test\r\nNICKNAME:Johnny\r\nEND:VCARD\r\n"
      expect(described_class.parse(vcard).nickname).to eq("Johnny")
    end

    it "extracts GENDER" do
      vcard = "BEGIN:VCARD\r\nVERSION:4.0\r\nUID:uid1\r\nFN:Test\r\nGENDER:F\r\nEND:VCARD\r\n"
      expect(described_class.parse(vcard).gender).to eq("F")
    end

    it "extracts PRONOUNS" do
      vcard = "BEGIN:VCARD\r\nVERSION:4.0\r\nUID:uid1\r\nFN:Test\r\nPRONOUNS:they/them\r\nEND:VCARD\r\n"
      expect(described_class.parse(vcard).pronouns).to eq("they/them")
    end

    it "extracts ROLE" do
      vcard = "BEGIN:VCARD\r\nVERSION:3.0\r\nUID:uid1\r\nFN:Test\r\nROLE:Project Lead\r\nEND:VCARD\r\n"
      expect(described_class.parse(vcard).role).to eq("Project Lead")
    end

    it "extracts IMPP with type" do
      vcard = "BEGIN:VCARD\r\nVERSION:3.0\r\nUID:uid1\r\nFN:Test\r\nIMPP;TYPE=xmpp:xmpp:user@example.com\r\nEND:VCARD\r\n"
      result = described_class.parse(vcard)
      expect(result.impp).to eq([{ type: "xmpp", value: "xmpp:user@example.com" }])
    end

    it "extracts X-SOCIALPROFILE" do
      vcard = "BEGIN:VCARD\r\nVERSION:3.0\r\nUID:uid1\r\nFN:Test\r\nX-SOCIALPROFILE;TYPE=twitter:https://twitter.com/user\r\nEND:VCARD\r\n"
      result = described_class.parse(vcard)
      expect(result.social_profiles).to eq([{ type: "twitter", value: "https://twitter.com/user" }])
    end

    it "extracts phonetic names" do
      vcard = "BEGIN:VCARD\r\nVERSION:3.0\r\nUID:uid1\r\nFN:Test\r\nX-PHONETIC-FIRST-NAME:Jon\r\nX-PHONETIC-LAST-NAME:Smiss\r\nEND:VCARD\r\n"
      result = described_class.parse(vcard)
      expect(result.phonetic_first_name).to eq("Jon")
      expect(result.phonetic_last_name).to eq("Smiss")
    end

    it "extracts GEO" do
      vcard = "BEGIN:VCARD\r\nVERSION:4.0\r\nUID:uid1\r\nFN:Test\r\nGEO:geo:37.386013,-122.082932\r\nEND:VCARD\r\n"
      expect(described_class.parse(vcard).geo).to eq("geo:37.386013,-122.082932")
    end

    it "extracts REV" do
      vcard = "BEGIN:VCARD\r\nVERSION:3.0\r\nUID:uid1\r\nFN:Test\r\nREV:20260324T120000Z\r\nEND:VCARD\r\n"
      expect(described_class.parse(vcard).rev).to eq("20260324T120000Z")
    end

    it "returns nil for missing new fields" do
      vcard = "BEGIN:VCARD\r\nVERSION:3.0\r\nUID:uid1\r\nFN:Test\r\nEND:VCARD\r\n"
      result = described_class.parse(vcard)
      expect(result.nickname).to be_nil
      expect(result.gender).to be_nil
      expect(result.pronouns).to be_nil
      expect(result.role).to be_nil
      expect(result.impp).to eq([])
      expect(result.social_profiles).to eq([])
      expect(result.phonetic_first_name).to be_nil
      expect(result.phonetic_last_name).to be_nil
      expect(result.geo).to be_nil
      expect(result.rev).to be_nil
    end
  end

  describe "new field generation" do
    it "generates N with all 5 components" do
      result = described_class.generate(first_name: "John", last_name: "Smith", middle_name: "Michael", name_prefix: "Dr.", name_suffix: "Jr.")
      expect(result).to include("N:Smith;John;Michael;Dr.;Jr.")
    end

    it "generates ADR from address hash" do
      result = described_class.generate(first_name: "Test", addresses: [{ type: "HOME", street: "123 Main", city: "Springfield", state: "IL", zip: "62701", country: "US" }])
      expect(result).to include("ADR;TYPE=HOME:;;123 Main;Springfield;IL;62701;US")
    end

    it "generates URL" do
      result = described_class.generate(first_name: "Test", urls: ["https://example.com"])
      expect(result).to include("URL:https://example.com")
    end

    it "generates BDAY and ANNIVERSARY" do
      result = described_class.generate(first_name: "Test", birthday: "1990-01-15", anniversary: "2015-06-20")
      expect(result).to include("BDAY:1990-01-15")
      expect(result).to include("ANNIVERSARY:2015-06-20")
    end

    it "generates NICKNAME" do
      result = described_class.generate(first_name: "Test", nickname: "Johnny")
      expect(result).to include("NICKNAME:Johnny")
    end

    it "generates GENDER, PRONOUNS, ROLE" do
      result = described_class.generate(first_name: "Test", gender: "M", pronouns: "he/him", role: "Engineer")
      expect(result).to include("GENDER:M")
      expect(result).to include("PRONOUNS:he/him")
      expect(result).to include("ROLE:Engineer")
    end

    it "generates IMPP" do
      result = described_class.generate(first_name: "Test", impp: [{ type: "xmpp", value: "xmpp:user@example.com" }])
      expect(result).to include("IMPP;TYPE=xmpp:xmpp:user@example.com")
    end

    it "generates X-SOCIALPROFILE" do
      result = described_class.generate(first_name: "Test", social_profiles: [{ type: "twitter", value: "https://twitter.com/user" }])
      expect(result).to include("X-SOCIALPROFILE;TYPE=twitter:https://twitter.com/user")
    end

    it "generates PHOTO from URL" do
      result = described_class.generate(first_name: "Test", photo_url: "https://example.com/photo.jpg")
      expect(result).to include("PHOTO;VALUE=uri:https://example.com/photo.jpg")
    end

    it "omits blank optional fields" do
      result = described_class.generate(first_name: "Test")
      expect(result).not_to include("NICKNAME")
      expect(result).not_to include("GENDER")
      expect(result).not_to include("PRONOUNS")
      expect(result).not_to include("ROLE")
      expect(result).not_to include("BDAY")
      expect(result).not_to include("ADR")
      expect(result).not_to include("URL:")
      expect(result).not_to include("IMPP")
      expect(result).not_to include("X-SOCIALPROFILE")
    end
  end

  describe "round-trip (generate → parse)" do
    it "preserves all fields" do
      params = {
        first_name: "John", last_name: "Smith", middle_name: "Michael",
        name_prefix: "Dr.", name_suffix: "Jr.",
        nickname: "Johnny", pronouns: "he/him", gender: "M", role: "Engineer",
        emails: ["john@example.com"], phones: ["+15551234"],
        organization: "Acme", title: "CTO", note: "A note",
        birthday: "1990-01-15", anniversary: "2015-06-20",
        urls: ["https://example.com"],
        addresses: [{ type: "HOME", street: "123 Main", city: "Springfield", state: "IL", zip: "62701", country: "US" }],
        impp: [{ type: "xmpp", value: "xmpp:john@example.com" }],
        social_profiles: [{ type: "twitter", value: "https://twitter.com/john" }],
        categories: ["Family", "Work"]
      }
      vcard = described_class.generate(params)
      parsed = described_class.parse(vcard)

      expect(parsed.first_name).to eq("John")
      expect(parsed.last_name).to eq("Smith")
      expect(parsed.middle_name).to eq("Michael")
      expect(parsed.name_prefix).to eq("Dr.")
      expect(parsed.name_suffix).to eq("Jr.")
      expect(parsed.nickname).to eq("Johnny")
      expect(parsed.pronouns).to eq("he/him")
      expect(parsed.gender).to eq("M")
      expect(parsed.role).to eq("Engineer")
      expect(parsed.organization).to eq("Acme")
      expect(parsed.title).to eq("CTO")
      expect(parsed.note).to eq("A note")
      expect(parsed.birthday).to eq("1990-01-15")
      expect(parsed.anniversary).to eq("2015-06-20")
      expect(parsed.emails.first[:value]).to eq("john@example.com")
      expect(parsed.phones.first[:value]).to eq("+15551234")
      expect(parsed.urls.first[:value]).to eq("https://example.com")
      expect(parsed.addresses.first[:street]).to eq("123 Main")
      expect(parsed.addresses.first[:city]).to eq("Springfield")
      expect(parsed.impp.first[:value]).to eq("xmpp:john@example.com")
      expect(parsed.social_profiles.first[:value]).to eq("https://twitter.com/john")
      expect(parsed.categories).to match_array(["Family", "Work"])
    end
  end
end
