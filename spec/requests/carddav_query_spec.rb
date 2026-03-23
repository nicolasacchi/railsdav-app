require "rails_helper"

RSpec.describe "CardDAV Query & Multiget", type: :request do
  let!(:user) { create(:user, username: "alice", password: "password123") }
  let(:ab) { user.addressbooks.first }
  let(:base) { "/dav/alice/contacts/default" }

  before do
    # Create 3 contacts with varying properties
    dav_put "#{base}/alice.vcf", body: <<~VCARD, user: user
      BEGIN:VCARD\r\nVERSION:3.0\r\nUID:uid-alice\r\nFN:Alice Smith\r\nEMAIL:alice@example.com\r\nTEL:+1234567890\r\nORG:Acme Corp\r\nNICKNAME:ally\r\nEND:VCARD
    VCARD
    dav_put "#{base}/bob.vcf", body: <<~VCARD, user: user
      BEGIN:VCARD\r\nVERSION:3.0\r\nUID:uid-bob\r\nFN:Bob Jones\r\nEMAIL:bob@test.org\r\nNICKNAME:bobby\r\nEND:VCARD
    VCARD
    dav_put "#{base}/carol.vcf", body: <<~VCARD, user: user
      BEGIN:VCARD\r\nVERSION:3.0\r\nUID:uid-carol\r\nFN:Carol Williams\r\nEMAIL:carol@example.com\r\nORG:Widgets Inc\r\nEND:VCARD
    VCARD
  end

  def query_xml(filters: "", limit: nil)
    limit_xml = limit ? "<card:limit><card:nresults>#{limit}</card:nresults></card:limit>" : ""
    <<~XML
      <?xml version="1.0" encoding="utf-8"?>
      <card:addressbook-query xmlns:d="DAV:" xmlns:card="urn:ietf:params:xml:ns:carddav">
        <d:prop>
          <d:getetag/>
          <card:address-data/>
        </d:prop>
        <card:filter>
          #{filters}
        </card:filter>
        #{limit_xml}
      </card:addressbook-query>
    XML
  end

  def prop_filter(name, match_type: "contains", text: nil, is_not_defined: false)
    if is_not_defined
      "<card:prop-filter name=\"#{name}\"><card:is-not-defined/></card:prop-filter>"
    elsif text
      "<card:prop-filter name=\"#{name}\"><card:text-match match-type=\"#{match_type}\">#{text}</card:text-match></card:prop-filter>"
    else
      "<card:prop-filter name=\"#{name}\"/>"
    end
  end

  describe "addressbook-query text-match" do
    it "contains on FN returns matching contacts" do
      dav_report "#{base}/", body: query_xml(filters: prop_filter("FN", text: "Alice")), user: user
      expect(response).to have_http_status(207)
      doc = parse_multistatus(response.body)
      hrefs = extract_hrefs(doc)
      expect(hrefs).to include(a_string_matching(/alice\.vcf/))
      expect(hrefs).not_to include(a_string_matching(/bob\.vcf/))
    end

    it "starts-with on FN" do
      dav_report "#{base}/", body: query_xml(filters: prop_filter("FN", match_type: "starts-with", text: "Bo")), user: user
      doc = parse_multistatus(response.body)
      hrefs = extract_hrefs(doc)
      expect(hrefs).to include(a_string_matching(/bob\.vcf/))
      expect(hrefs.size).to eq(1)
    end

    it "ends-with on NICKNAME" do
      dav_report "#{base}/", body: query_xml(filters: prop_filter("NICKNAME", match_type: "ends-with", text: "by")), user: user
      doc = parse_multistatus(response.body)
      hrefs = extract_hrefs(doc)
      expect(hrefs).to include(a_string_matching(/bob\.vcf/))
      expect(hrefs.size).to eq(1)
    end

    it "equals on EMAIL" do
      dav_report "#{base}/", body: query_xml(filters: prop_filter("EMAIL", match_type: "equals", text: "bob@test.org")), user: user
      doc = parse_multistatus(response.body)
      hrefs = extract_hrefs(doc)
      expect(hrefs).to include(a_string_matching(/bob\.vcf/))
      expect(hrefs.size).to eq(1)
    end

    it "is case-insensitive" do
      dav_report "#{base}/", body: query_xml(filters: prop_filter("FN", text: "ALICE")), user: user
      doc = parse_multistatus(response.body)
      expect(extract_hrefs(doc)).to include(a_string_matching(/alice\.vcf/))
    end
  end

  describe "multiple prop-filters" do
    it "applies all filters (allof)" do
      filters = prop_filter("FN", text: "l") + prop_filter("ORG")
      dav_report "#{base}/", body: query_xml(filters: filters), user: user
      doc = parse_multistatus(response.body)
      hrefs = extract_hrefs(doc)
      # Alice has FN with "l" and ORG, Carol has FN with "l" and ORG
      expect(hrefs).to all(satisfy { |h| h.match?(/alice|carol/) })
    end
  end

  describe "property existence" do
    it "prop-filter without text-match returns contacts with that property" do
      dav_report "#{base}/", body: query_xml(filters: prop_filter("ORG")), user: user
      doc = parse_multistatus(response.body)
      hrefs = extract_hrefs(doc)
      expect(hrefs).to include(a_string_matching(/alice\.vcf/))
      expect(hrefs).to include(a_string_matching(/carol\.vcf/))
      expect(hrefs).not_to include(a_string_matching(/bob\.vcf/))
    end

    it "is-not-defined returns contacts without that property" do
      dav_report "#{base}/", body: query_xml(filters: prop_filter("ORG", is_not_defined: true)), user: user
      doc = parse_multistatus(response.body)
      hrefs = extract_hrefs(doc)
      expect(hrefs).to include(a_string_matching(/bob\.vcf/))
      expect(hrefs).not_to include(a_string_matching(/alice\.vcf/))
    end
  end

  describe "nresults limit" do
    it "returns at most 1 contact" do
      dav_report "#{base}/", body: query_xml(limit: 1), user: user
      doc = parse_multistatus(response.body)
      expect(extract_hrefs(doc).size).to eq(1)
    end

    it "returns at most 2 contacts" do
      dav_report "#{base}/", body: query_xml(limit: 2), user: user
      doc = parse_multistatus(response.body)
      expect(extract_hrefs(doc).size).to eq(2)
    end
  end

  describe "various property searches" do
    it "matches on EMAIL containing domain" do
      dav_report "#{base}/", body: query_xml(filters: prop_filter("EMAIL", text: "example.com")), user: user
      doc = parse_multistatus(response.body)
      hrefs = extract_hrefs(doc)
      expect(hrefs.size).to eq(2) # alice + carol
    end

    it "matches on TEL" do
      dav_report "#{base}/", body: query_xml(filters: prop_filter("TEL", text: "+1234")), user: user
      doc = parse_multistatus(response.body)
      expect(extract_hrefs(doc)).to include(a_string_matching(/alice\.vcf/))
    end

    it "returns empty for non-existent property" do
      dav_report "#{base}/", body: query_xml(filters: prop_filter("X-FOOBAR", text: "anything")), user: user
      doc = parse_multistatus(response.body)
      expect(extract_hrefs(doc)).to be_empty
    end

    it "returns all contacts with empty filter" do
      xml = <<~XML
        <?xml version="1.0" encoding="utf-8"?>
        <card:addressbook-query xmlns:d="DAV:" xmlns:card="urn:ietf:params:xml:ns:carddav">
          <d:prop><d:getetag/><card:address-data/></d:prop>
          <card:filter/>
        </card:addressbook-query>
      XML
      dav_report "#{base}/", body: xml, user: user
      doc = parse_multistatus(response.body)
      expect(extract_hrefs(doc).size).to eq(3)
    end
  end

  describe "multiget edge cases" do
    it "returns proper statuses for mix of existing and non-existing" do
      xml = <<~XML
        <?xml version="1.0" encoding="utf-8"?>
        <card:addressbook-multiget xmlns:d="DAV:" xmlns:card="urn:ietf:params:xml:ns:carddav">
          <d:prop><d:getetag/><card:address-data/></d:prop>
          <d:href>#{base}/alice.vcf</d:href>
          <d:href>#{base}/nonexistent.vcf</d:href>
          <d:href>#{base}/carol.vcf</d:href>
        </card:addressbook-multiget>
      XML
      dav_report "#{base}/", body: xml, user: user
      expect(response).to have_http_status(207)
      doc = parse_multistatus(response.body)

      alice_resp = find_response(doc, "#{base}/alice.vcf")
      expect(alice_resp).to be_present

      nonexist_resp = find_response(doc, "#{base}/nonexistent.vcf")
      expect(nonexist_resp.at_xpath(".//d:status", NAMESPACES).text).to include("404")
    end
  end
end
