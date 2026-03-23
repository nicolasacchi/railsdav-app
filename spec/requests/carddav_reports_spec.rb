require "rails_helper"

RSpec.describe "CardDAV REPORT Methods", type: :request do
  let!(:user) { create(:user, username: "alice", password: "password123") }
  let(:addressbook) { user.addressbooks.find_by(uri: "default") }

  let(:vcard1) { "BEGIN:VCARD\r\nVERSION:3.0\r\nUID:uid-001\r\nFN:John Doe\r\nN:Doe;John;;;\r\nEMAIL:john@example.com\r\nEND:VCARD\r\n" }
  let(:vcard2) { "BEGIN:VCARD\r\nVERSION:3.0\r\nUID:uid-002\r\nFN:Jane Smith\r\nN:Smith;Jane;;;\r\nEMAIL:jane@example.com\r\nEND:VCARD\r\n" }
  let(:vcard3) { "BEGIN:VCARD\r\nVERSION:3.0\r\nUID:uid-003\r\nFN:Bob Wilson\r\nN:Wilson;Bob;;;\r\nEND:VCARD\r\n" }

  before do
    dav_put "/dav/alice/contacts/default/john.vcf", body: vcard1, user: user
    dav_put "/dav/alice/contacts/default/jane.vcf", body: vcard2, user: user
    dav_put "/dav/alice/contacts/default/bob.vcf", body: vcard3, user: user
  end

  describe "addressbook-multiget (RFC 6352 Section 8.7)" do
    it "returns requested vCards in 207 response" do
      body = <<~XML
        <?xml version="1.0" encoding="utf-8"?>
        <card:addressbook-multiget xmlns:d="DAV:" xmlns:card="urn:ietf:params:xml:ns:carddav">
          <d:prop>
            <d:getetag/>
            <card:address-data/>
          </d:prop>
          <d:href>/dav/alice/contacts/default/john.vcf</d:href>
          <d:href>/dav/alice/contacts/default/jane.vcf</d:href>
        </card:addressbook-multiget>
      XML
      dav_report "/dav/alice/contacts/default/", body: body, user: user
      expect(response).to have_http_status(207)
      doc = parse_multistatus(response.body)
      hrefs = extract_hrefs(doc)
      expect(hrefs).to contain_exactly(
        "/dav/alice/contacts/default/john.vcf",
        "/dav/alice/contacts/default/jane.vcf"
      )
    end

    it "includes address-data with full vCard" do
      body = <<~XML
        <?xml version="1.0" encoding="utf-8"?>
        <card:addressbook-multiget xmlns:d="DAV:" xmlns:card="urn:ietf:params:xml:ns:carddav">
          <d:prop><card:address-data/></d:prop>
          <d:href>/dav/alice/contacts/default/john.vcf</d:href>
        </card:addressbook-multiget>
      XML
      dav_report "/dav/alice/contacts/default/", body: body, user: user
      doc = parse_multistatus(response.body)
      addr_data = doc.at_xpath("//card:address-data", NAMESPACES)
      expect(addr_data).to be_present
      expect(addr_data.text).to include("John Doe")
    end

    it "includes getetag for each response" do
      body = <<~XML
        <?xml version="1.0" encoding="utf-8"?>
        <card:addressbook-multiget xmlns:d="DAV:" xmlns:card="urn:ietf:params:xml:ns:carddav">
          <d:prop><d:getetag/></d:prop>
          <d:href>/dav/alice/contacts/default/john.vcf</d:href>
        </card:addressbook-multiget>
      XML
      dav_report "/dav/alice/contacts/default/", body: body, user: user
      doc = parse_multistatus(response.body)
      etag = doc.at_xpath("//d:getetag", NAMESPACES)
      expect(etag).to be_present
      expect(etag.text).to match(/^"[a-f0-9]{64}"$/)
    end

    it "returns 404 status for non-existent hrefs" do
      body = <<~XML
        <?xml version="1.0" encoding="utf-8"?>
        <card:addressbook-multiget xmlns:d="DAV:" xmlns:card="urn:ietf:params:xml:ns:carddav">
          <d:prop><d:getetag/></d:prop>
          <d:href>/dav/alice/contacts/default/nonexistent.vcf</d:href>
        </card:addressbook-multiget>
      XML
      dav_report "/dav/alice/contacts/default/", body: body, user: user
      doc = parse_multistatus(response.body)
      resp = find_response(doc, "/dav/alice/contacts/default/nonexistent.vcf")
      expect(resp).to be_present
      status = resp.at_xpath("d:status", NAMESPACES)
      expect(status.text).to include("404")
    end
  end

  describe "addressbook-query (RFC 6352 Section 8.6)" do
    it "returns all contacts when no filter is provided" do
      body = <<~XML
        <?xml version="1.0" encoding="utf-8"?>
        <card:addressbook-query xmlns:d="DAV:" xmlns:card="urn:ietf:params:xml:ns:carddav">
          <d:prop>
            <d:getetag/>
            <card:address-data/>
          </d:prop>
        </card:addressbook-query>
      XML
      dav_report "/dav/alice/contacts/default/", body: body, user: user
      expect(response).to have_http_status(207)
      doc = parse_multistatus(response.body)
      hrefs = extract_hrefs(doc)
      expect(hrefs.length).to eq(3)
    end

    it "filters by FN text-match" do
      body = <<~XML
        <?xml version="1.0" encoding="utf-8"?>
        <card:addressbook-query xmlns:d="DAV:" xmlns:card="urn:ietf:params:xml:ns:carddav">
          <d:prop><d:getetag/><card:address-data/></d:prop>
          <card:filter>
            <card:prop-filter name="FN">
              <card:text-match match-type="contains">John</card:text-match>
            </card:prop-filter>
          </card:filter>
        </card:addressbook-query>
      XML
      dav_report "/dav/alice/contacts/default/", body: body, user: user
      doc = parse_multistatus(response.body)
      hrefs = extract_hrefs(doc)
      expect(hrefs).to contain_exactly("/dav/alice/contacts/default/john.vcf")
    end
  end

  describe "sync-collection (RFC 6578 Section 3)" do
    it "returns all contacts with empty sync-token (initial sync)" do
      body = <<~XML
        <?xml version="1.0" encoding="utf-8"?>
        <d:sync-collection xmlns:d="DAV:" xmlns:card="urn:ietf:params:xml:ns:carddav">
          <d:sync-token/>
          <d:prop>
            <d:getetag/>
          </d:prop>
        </d:sync-collection>
      XML
      dav_report "/dav/alice/contacts/default/", body: body, user: user
      expect(response).to have_http_status(207)
      doc = parse_multistatus(response.body)
      hrefs = extract_hrefs(doc)
      expect(hrefs.length).to eq(3)
      # Should include a new sync-token
      st = doc.at_xpath("//d:multistatus/d:sync-token", NAMESPACES)
      expect(st).to be_present
      expect(st.text).to match(%r{/ns/sync/\d+})
    end

    it "returns only new contacts after incremental sync" do
      # Get current sync token
      current_token = addressbook.reload.sync_token_url

      # Add a new contact
      new_vcard = "BEGIN:VCARD\r\nVERSION:3.0\r\nUID:uid-004\r\nFN:New Person\r\nEND:VCARD\r\n"
      dav_put "/dav/alice/contacts/default/new.vcf", body: new_vcard, user: user

      body = <<~XML
        <?xml version="1.0" encoding="utf-8"?>
        <d:sync-collection xmlns:d="DAV:" xmlns:card="urn:ietf:params:xml:ns:carddav">
          <d:sync-token>#{current_token}</d:sync-token>
          <d:prop><d:getetag/></d:prop>
        </d:sync-collection>
      XML
      dav_report "/dav/alice/contacts/default/", body: body, user: user
      doc = parse_multistatus(response.body)
      hrefs = extract_hrefs(doc)
      expect(hrefs).to contain_exactly("/dav/alice/contacts/default/new.vcf")
    end

    it "reports deleted contacts with 404 status" do
      current_token = addressbook.reload.sync_token_url

      dav_delete "/dav/alice/contacts/default/bob.vcf", user: user

      body = <<~XML
        <?xml version="1.0" encoding="utf-8"?>
        <d:sync-collection xmlns:d="DAV:" xmlns:card="urn:ietf:params:xml:ns:carddav">
          <d:sync-token>#{current_token}</d:sync-token>
          <d:prop><d:getetag/></d:prop>
        </d:sync-collection>
      XML
      dav_report "/dav/alice/contacts/default/", body: body, user: user
      doc = parse_multistatus(response.body)
      resp = find_response(doc, "/dav/alice/contacts/default/bob.vcf")
      expect(resp).to be_present
      status = resp.at_xpath("d:status", NAMESPACES)
      expect(status.text).to include("404")
    end

    it "returns 403 with valid-sync-token error for invalid token" do
      body = <<~XML
        <?xml version="1.0" encoding="utf-8"?>
        <d:sync-collection xmlns:d="DAV:" xmlns:card="urn:ietf:params:xml:ns:carddav">
          <d:sync-token>invalid-token</d:sync-token>
          <d:prop><d:getetag/></d:prop>
        </d:sync-collection>
      XML
      dav_report "/dav/alice/contacts/default/", body: body, user: user
      expect(response).to have_http_status(403)
      doc = Nokogiri::XML(response.body)
      error = doc.at_xpath("//d:valid-sync-token", NAMESPACES)
      expect(error).to be_present
    end

    it "reports modified contacts after update" do
      current_token = addressbook.reload.sync_token_url

      updated = vcard1.sub("John Doe", "John M. Doe")
      dav_put "/dav/alice/contacts/default/john.vcf", body: updated, user: user

      body = <<~XML
        <?xml version="1.0" encoding="utf-8"?>
        <d:sync-collection xmlns:d="DAV:" xmlns:card="urn:ietf:params:xml:ns:carddav">
          <d:sync-token>#{current_token}</d:sync-token>
          <d:prop><d:getetag/></d:prop>
        </d:sync-collection>
      XML
      dav_report "/dav/alice/contacts/default/", body: body, user: user
      doc = parse_multistatus(response.body)
      hrefs = extract_hrefs(doc)
      expect(hrefs).to contain_exactly("/dav/alice/contacts/default/john.vcf")
    end
  end
end
