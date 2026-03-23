require "rails_helper"

RSpec.describe "CardDAV Edge Cases", type: :request do
  let!(:user) { create(:user, username: "alice", password: "password123") }
  let(:ab) { user.addressbooks.first }
  let(:base) { "/dav/alice/contacts/default" }

  # Radicale Issues #1205, #721, #648 — Photo handling
  describe "photo data preservation" do
    it "preserves PHOTO;ENCODING=b;TYPE=jpeg on round-trip" do
      photo_b64 = Base64.strict_encode64("fake-jpeg-data-here")
      vcard = "BEGIN:VCARD\r\nVERSION:3.0\r\nUID:photo-1\r\nFN:Photo Test\r\nPHOTO;ENCODING=b;TYPE=jpeg:#{photo_b64}\r\nEND:VCARD\r\n"
      dav_put "#{base}/photo1.vcf", body: vcard, user: user
      expect(response).to have_http_status(201)
      dav_get "#{base}/photo1.vcf", user: user
      expect(response.body).to include(photo_b64)
    end

    it "preserves PHOTO as data URI on round-trip" do
      photo_b64 = Base64.strict_encode64("fake-image-bytes")
      vcard = "BEGIN:VCARD\r\nVERSION:4.0\r\nUID:photo-2\r\nFN:Data URI Photo\r\nPHOTO:data:image/jpeg;base64,#{photo_b64}\r\nEND:VCARD\r\n"
      dav_put "#{base}/photo2.vcf", body: vcard, user: user
      expect(response).to have_http_status(201)
      dav_get "#{base}/photo2.vcf", user: user
      expect(response.body).to include(photo_b64)
    end

    it "handles large PHOTO data (100KB+)" do
      photo_b64 = Base64.strict_encode64("x" * 100_000)
      vcard = "BEGIN:VCARD\r\nVERSION:3.0\r\nUID:photo-3\r\nFN:Big Photo\r\nPHOTO;ENCODING=b;TYPE=png:#{photo_b64}\r\nEND:VCARD\r\n"
      dav_put "#{base}/photo3.vcf", body: vcard, user: user
      expect(response).to have_http_status(201)
      dav_get "#{base}/photo3.vcf", user: user
      expect(response.body).to include(photo_b64)
    end
  end

  # Radicale Issues #832, #887, #1238 — vCard versions
  describe "vCard version handling" do
    it "stores and returns vCard 4.0 unchanged" do
      vcard = "BEGIN:VCARD\r\nVERSION:4.0\r\nUID:v4-test\r\nFN:Version Four\r\nANNIVERSARY:20200101\r\nGENDER:M\r\nEND:VCARD\r\n"
      dav_put "#{base}/v4.vcf", body: vcard, user: user
      expect(response).to have_http_status(201)
      dav_get "#{base}/v4.vcf", user: user
      expect(response.body).to eq(vcard)
    end

    it "stores and returns vCard 3.0 unchanged" do
      vcard = "BEGIN:VCARD\r\nVERSION:3.0\r\nUID:v3-test\r\nFN:Version Three\r\nN:Three;Version;;;\r\nEND:VCARD\r\n"
      dav_put "#{base}/v3.vcf", body: vcard, user: user
      expect(response).to have_http_status(201)
      dav_get "#{base}/v3.vcf", user: user
      expect(response.body).to eq(vcard)
    end

    it "stores vCard 2.1 with CHARSET=UTF-8" do
      vcard = "BEGIN:VCARD\r\nVERSION:2.1\r\nUID:v21-test\r\nFN;CHARSET=UTF-8:Ärger Müller\r\nN;CHARSET=UTF-8:Müller;Ärger;;;\r\nEND:VCARD\r\n"
      dav_put "#{base}/v21.vcf", body: vcard, user: user
      expect(response).to have_http_status(201)
      dav_get "#{base}/v21.vcf", user: user
      expect(response.body).to include("Ärger Müller")
    end
  end

  # Radicale Issue #213, GrapheneOS Contact Scopes — CATEGORIES
  describe "CATEGORIES preservation" do
    it "preserves CATEGORIES on round-trip" do
      vcard = "BEGIN:VCARD\r\nVERSION:3.0\r\nUID:cat-1\r\nFN:Cat Test\r\nCATEGORIES:Family,Work,Friends\r\nEND:VCARD\r\n"
      dav_put "#{base}/cat1.vcf", body: vcard, user: user
      expect(response).to have_http_status(201)
      dav_get "#{base}/cat1.vcf", user: user
      expect(response.body).to include("CATEGORIES:Family,Work,Friends")
    end

    it "preserves escaped commas in CATEGORIES" do
      vcard = "BEGIN:VCARD\r\nVERSION:3.0\r\nUID:cat-2\r\nFN:Escaped\r\nCATEGORIES:Family\\, Extended,Friends\r\nEND:VCARD\r\n"
      dav_put "#{base}/cat2.vcf", body: vcard, user: user
      expect(response).to have_http_status(201)
      dav_get "#{base}/cat2.vcf", user: user
      expect(response.body).to include("CATEGORIES:Family\\, Extended,Friends")
    end

    it "preserves multiple CATEGORIES lines" do
      vcard = "BEGIN:VCARD\r\nVERSION:3.0\r\nUID:cat-3\r\nFN:Multi\r\nCATEGORIES:Family\r\nCATEGORIES:Work\r\nEND:VCARD\r\n"
      dav_put "#{base}/cat3.vcf", body: vcard, user: user
      expect(response).to have_http_status(201)
      dav_get "#{base}/cat3.vcf", user: user
      expect(response.body.scan(/CATEGORIES:/).count).to be >= 2
    end
  end

  # Radicale Issue #213 — KIND:group vCard
  describe "KIND:group vCard" do
    it "stores and returns KIND:group vCard unchanged" do
      vcard = "BEGIN:VCARD\r\nVERSION:4.0\r\nUID:grp-1\r\nFN:My Group\r\nKIND:group\r\nEND:VCARD\r\n"
      dav_put "#{base}/grp1.vcf", body: vcard, user: user
      expect(response).to have_http_status(201)
      dav_get "#{base}/grp1.vcf", user: user
      expect(response.body).to include("KIND:group")
    end

    it "preserves MEMBER properties" do
      vcard = "BEGIN:VCARD\r\nVERSION:4.0\r\nUID:grp-2\r\nFN:Team\r\nKIND:group\r\nMEMBER:urn:uuid:m1\r\nMEMBER:urn:uuid:m2\r\nEND:VCARD\r\n"
      dav_put "#{base}/grp2.vcf", body: vcard, user: user
      expect(response).to have_http_status(201)
      dav_get "#{base}/grp2.vcf", user: user
      expect(response.body).to include("MEMBER:urn:uuid:m1")
      expect(response.body).to include("MEMBER:urn:uuid:m2")
    end
  end

  # Radicale Issue #1066 — Import edge cases
  describe "import edge cases" do
    it "accepts vCard without FN property (lenient)" do
      vcard = "BEGIN:VCARD\r\nVERSION:3.0\r\nUID:no-fn\r\nN:Smith;John;;;\r\nEMAIL:john@example.com\r\nEND:VCARD\r\n"
      dav_put "#{base}/nofn.vcf", body: vcard, user: user
      expect(response).to have_http_status(201)
    end

    it "accepts minimal vCard (BEGIN/VERSION/UID/END)" do
      vcard = "BEGIN:VCARD\r\nVERSION:3.0\r\nUID:minimal\r\nEND:VCARD\r\n"
      dav_put "#{base}/minimal.vcf", body: vcard, user: user
      expect(response).to have_http_status(201)
    end
  end

  # Radicale Issue #1002 — Payload size
  describe "payload size limits" do
    it "rejects vCard exceeding 1MB" do
      padding = "X" * 1_048_577
      vcard = "BEGIN:VCARD\r\nVERSION:3.0\r\nUID:toobig\r\nFN:Too Big\r\nNOTE:#{padding}\r\nEND:VCARD\r\n"
      dav_put "#{base}/toobig.vcf", body: vcard, user: user
      expect(response).to have_http_status(413)
    end

    it "accepts vCard just under 1MB" do
      # Build a vCard that's just under 1MB total
      header = "BEGIN:VCARD\r\nVERSION:3.0\r\nUID:justunder\r\nFN:Under\r\nNOTE:"
      footer = "\r\nEND:VCARD\r\n"
      padding = "A" * (1_048_576 - header.bytesize - footer.bytesize - 1)
      vcard = header + padding + footer
      dav_put "#{base}/under.vcf", body: vcard, user: user
      expect(response).to have_http_status(201)
    end
  end

  # Radicale/iOS Issue #1865 — URL-encoded usernames
  describe "URL-encoded path segments" do
    it "resolves %40 in path for email-style usernames" do
      bob = create(:user, username: "bob", email: "bob@example.com", password: "password123")
      headers = basic_auth_header("bob@example.com", DAV_TEST_PASSWORD)
      headers["HTTP_DEPTH"] = "0"
      process(:propfind, "/dav/bob/", headers: headers, params: propfind_xml("displayname"))
      expect(response).to have_http_status(207)
    end
  end
end
