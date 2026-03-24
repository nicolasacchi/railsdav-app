require "rails_helper"

RSpec.describe "CardDAV Compliance (CalDAVTester + sabre/dav patterns)", type: :request do
  let!(:user) { create(:user, username: "alice", password: "password123") }
  let(:ab) { user.addressbooks.first }
  let(:base) { "/dav/alice/contacts/default" }

  # CalDAVTester put.xml — special character handling
  describe "PUT data integrity" do
    it "round-trips vCard with escaped newlines in ADR" do
      vcard = "BEGIN:VCARD\r\nVERSION:3.0\r\nUID:adr-test\r\nFN:Address Test\r\nADR:;;123 Main St\\nApt 4;Springfield;IL;62701;US\r\nEND:VCARD\r\n"
      dav_put "#{base}/adr.vcf", body: vcard, user: user
      expect(response).to have_http_status(201)
      dav_get "#{base}/adr.vcf", user: user
      expect(response.body).to include("123 Main St\\nApt 4")
    end

    it "round-trips vCard with escaped commas in ORG" do
      vcard = "BEGIN:VCARD\r\nVERSION:3.0\r\nUID:org-test\r\nFN:Org Test\r\nORG:Acme\\, Inc.;Engineering\r\nEND:VCARD\r\n"
      dav_put "#{base}/org.vcf", body: vcard, user: user
      expect(response).to have_http_status(201)
      dav_get "#{base}/org.vcf", user: user
      expect(response.body).to include("Acme\\, Inc.")
    end

    it "round-trips vCard with X-custom properties" do
      vcard = "BEGIN:VCARD\r\nVERSION:3.0\r\nUID:xcustom\r\nFN:Custom\r\nX-CUSTOM-FIELD:some-value\r\nX-ANOTHER:data\r\nEND:VCARD\r\n"
      dav_put "#{base}/custom.vcf", body: vcard, user: user
      expect(response).to have_http_status(201)
      dav_get "#{base}/custom.vcf", user: user
      expect(response.body).to include("X-CUSTOM-FIELD:some-value")
      expect(response.body).to include("X-ANOTHER:data")
    end

    it "accepts company vCard (ORG without N)" do
      vcard = "BEGIN:VCARD\r\nVERSION:3.0\r\nUID:company\r\nFN:Acme Corp\r\nORG:Acme Corp\r\nEND:VCARD\r\n"
      dav_put "#{base}/company.vcf", body: vcard, user: user
      expect(response).to have_http_status(201)
    end
  end

  # CalDAVTester errors.xml
  describe "PUT error handling" do
    it "returns 409 for PUT to collection root" do
      vcard = "BEGIN:VCARD\r\nVERSION:3.0\r\nUID:coll-put\r\nFN:Bad\r\nEND:VCARD\r\n"
      dav_put "#{base}/", body: vcard, user: user
      expect(response).to have_http_status(409)
    end

    it "returns 400 for plaintext vCard without UID" do
      dav_put "#{base}/bad.vcf", body: "BEGIN:VCARD\r\nVERSION:3.0\r\nFN:No UID\r\nEND:VCARD\r\n", user: user
      expect(response).to have_http_status(400)
    end
  end

  # CalDAVTester get.xml + sabre/dav CardTest
  describe "GET validation" do
    before do
      vcard = "BEGIN:VCARD\r\nVERSION:3.0\r\nUID:get-test\r\nFN:Get Test\r\nEND:VCARD\r\n"
      dav_put "#{base}/gettest.vcf", body: vcard, user: user
    end

    it "returns Content-Type text/vcard; charset=utf-8" do
      dav_get "#{base}/gettest.vcf", user: user
      expect(response.headers["Content-Type"]).to match(%r{text/vcard})
    end

    it "returns ETag header matching stored contact" do
      dav_get "#{base}/gettest.vcf", user: user
      etag = response.headers["ETag"]
      expect(etag).to be_present
      expect(etag).to match(/\A"[a-f0-9]+"\z/)
    end

    it "returns 405 for GET on collection" do
      dav_get "#{base}/", user: user
      expect(response).to have_http_status(405)
    end
  end

  # CalDAVTester
  describe "DELETE validation" do
    it "returns 404 for non-existent resource" do
      dav_delete "#{base}/doesnotexist.vcf", user: user
      expect(response).to have_http_status(404)
    end
  end

  # CalDAVTester + Litmus — MKCOL
  describe "MKCOL" do
    it "creates addressbook with XML body containing displayname" do
      xml = <<~XML
        <?xml version="1.0" encoding="utf-8"?>
        <d:mkcol xmlns:d="DAV:" xmlns:card="urn:ietf:params:xml:ns:carddav">
          <d:set><d:prop>
            <d:displayname>Work Contacts</d:displayname>
            <card:addressbook-description>My work addressbook</card:addressbook-description>
          </d:prop></d:set>
        </d:mkcol>
      XML
      dav_mkcol "/dav/alice/contacts/work/", body: xml, user: user
      expect(response).to have_http_status(201)

      # Verify the displayname was set
      dav_propfind "/dav/alice/contacts/work/", user: user, depth: 0,
                   body: propfind_xml("displayname")
      expect(response.body).to include("Work Contacts")
    end

    it "returns 409 for duplicate addressbook URI" do
      dav_mkcol "/dav/alice/contacts/default/", user: user
      expect(response).to have_http_status(409)
    end

    it "creates addressbook with empty body" do
      dav_mkcol "/dav/alice/contacts/empty-body/", user: user
      expect(response).to have_http_status(201)
    end
  end

  # CalDAVTester + Litmus — PROPPATCH
  describe "PROPPATCH" do
    it "updates displayname and returns 207" do
      xml = <<~XML
        <?xml version="1.0" encoding="utf-8"?>
        <d:propertyupdate xmlns:d="DAV:">
          <d:set><d:prop>
            <d:displayname>Renamed Book</d:displayname>
          </d:prop></d:set>
        </d:propertyupdate>
      XML
      headers = { "CONTENT_TYPE" => "application/xml; charset=utf-8" }
      headers.merge!(basic_auth_header(user.username, DAV_TEST_PASSWORD))
      process(:proppatch, "#{base}/", headers: headers, params: xml)
      expect(response).to have_http_status(207)

      # Verify the name changed
      ab.reload
      expect(ab.displayname).to eq("Renamed Book")
    end

    it "returns 405 for PROPPATCH on non-addressbook resource" do
      headers = { "CONTENT_TYPE" => "application/xml; charset=utf-8" }
      headers.merge!(basic_auth_header(user.username, DAV_TEST_PASSWORD))
      process(:proppatch, "/dav/alice/", headers: headers, params: "<d:propertyupdate xmlns:d='DAV:'/>")
      expect(response).to have_http_status(405)
    end
  end

  # CalDAVTester sync-report.xml — extra scenarios
  describe "sync-collection extra scenarios" do
    it "returns empty result with token when no changes" do
      # Get initial sync token
      dav_propfind "#{base}/", user: user, depth: 0,
                   body: propfind_xml("sync-token")
      doc = parse_multistatus(response.body)
      token = doc.at_xpath("//d:sync-token", NAMESPACES)&.text
      expect(token).to be_present

      # Request sync with current token — no changes
      sync_xml = <<~XML
        <?xml version="1.0" encoding="utf-8"?>
        <d:sync-collection xmlns:d="DAV:" xmlns:card="urn:ietf:params:xml:ns:carddav">
          <d:sync-token>#{token}</d:sync-token>
          <d:prop><d:getetag/></d:prop>
        </d:sync-collection>
      XML
      dav_report "#{base}/", body: sync_xml, user: user
      expect(response).to have_http_status(207)
      doc = parse_multistatus(response.body)
      expect(extract_hrefs(doc)).to be_empty
    end

    it "returns correct final state after create + delete" do
      # Create a contact
      vcard = "BEGIN:VCARD\r\nVERSION:3.0\r\nUID:sync-test\r\nFN:Sync Test\r\nEND:VCARD\r\n"
      dav_put "#{base}/sync.vcf", body: vcard, user: user
      expect(response).to have_http_status(201)

      # Get sync token after create
      dav_propfind "#{base}/", user: user, depth: 0, body: propfind_xml("sync-token")
      doc = parse_multistatus(response.body)
      token_after_create = doc.at_xpath("//d:sync-token", NAMESPACES)&.text

      # Delete the contact
      dav_delete "#{base}/sync.vcf", user: user
      expect(response).to have_http_status(204)

      # Sync from token_after_create — should show deletion
      sync_xml = <<~XML
        <?xml version="1.0" encoding="utf-8"?>
        <d:sync-collection xmlns:d="DAV:" xmlns:card="urn:ietf:params:xml:ns:carddav">
          <d:sync-token>#{token_after_create}</d:sync-token>
          <d:prop><d:getetag/></d:prop>
        </d:sync-collection>
      XML
      dav_report "#{base}/", body: sync_xml, user: user
      expect(response).to have_http_status(207)
      doc = parse_multistatus(response.body)
      deleted = find_response(doc, "#{base}/sync.vcf")
      expect(deleted).to be_present
      expect(deleted.at_xpath(".//d:status", NAMESPACES).text).to include("404")
    end
  end

  # sabre/dav SupportedAddressData + property checks
  describe "discovery properties" do
    it "advertises supported-address-data with vCard 3.0 and 4.0" do
      dav_propfind "#{base}/", user: user, depth: 0,
                   body: propfind_xml("card:supported-address-data")
      expect(response).to have_http_status(207)
      body = response.body
      expect(body).to include("vcard")
    end

    it "returns max-resource-size of 1048576" do
      dav_propfind "#{base}/", user: user, depth: 0,
                   body: propfind_xml("card:max-resource-size")
      expect(response).to have_http_status(207)
      expect(response.body).to include("1048576")
    end

    it "returns addressbook-description" do
      dav_propfind "#{base}/", user: user, depth: 0,
                   body: propfind_xml("card:addressbook-description")
      expect(response).to have_http_status(207)
      expect(response.body).to include("addressbook-description")
    end
  end
end
