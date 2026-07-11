require "rails_helper"

# Coverage for the filter/@test (anyof vs allof) semantics in addressbook-query.
RSpec.describe "CardDAV addressbook-query filter test attribute", type: :request do
  include DavHelpers

  let!(:user) { create(:user, username: "alice", password: "password123") }
  let(:base) { "/dav/alice/contacts/default" }

  before do
    dav_put "#{base}/alice.vcf", body: "BEGIN:VCARD\r\nVERSION:3.0\r\nUID:uid-alice\r\nFN:Alice\r\nEMAIL:alice@example.com\r\nEND:VCARD", user: user
    dav_put "#{base}/bob.vcf",   body: "BEGIN:VCARD\r\nVERSION:3.0\r\nUID:uid-bob\r\nFN:Bob\r\nORG:Acme\r\nEND:VCARD", user: user
  end

  def query(test:)
    <<~XML
      <?xml version="1.0" encoding="utf-8"?>
      <card:addressbook-query xmlns:d="DAV:" xmlns:card="urn:ietf:params:xml:ns:carddav">
        <d:prop><d:getetag/></d:prop>
        <card:filter test="#{test}">
          <card:prop-filter name="FN"><card:text-match match-type="contains">Alice</card:text-match></card:prop-filter>
          <card:prop-filter name="ORG"><card:text-match match-type="contains">Acme</card:text-match></card:prop-filter>
        </card:filter>
      </card:addressbook-query>
    XML
  end

  def hrefs
    Nokogiri::XML(response.body).remove_namespaces!.xpath("//response/href").map(&:text)
  end

  it "anyof returns the union (FN=Alice OR ORG=Acme)" do
    dav_report "#{base}/", body: query(test: "anyof"), user: user
    expect(response).to have_http_status(207)
    expect(hrefs).to include(a_string_matching(/alice\.vcf/))
    expect(hrefs).to include(a_string_matching(/bob\.vcf/))
  end

  it "allof returns the intersection (no contact has both)" do
    dav_report "#{base}/", body: query(test: "allof"), user: user
    expect(response).to have_http_status(207)
    expect(hrefs).not_to include(a_string_matching(/alice\.vcf/))
    expect(hrefs).not_to include(a_string_matching(/bob\.vcf/))
  end
end
