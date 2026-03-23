require "rails_helper"

RSpec.describe "CardDAV Discovery Chain", type: :request do
  let!(:user) { create(:user, username: "alice", password: "password123") }

  describe "Step 0: Well-Known redirect (RFC 6764)" do
    it "GET /.well-known/carddav returns 301 to /dav/" do
      get "/.well-known/carddav"
      expect(response).to have_http_status(301)
      expect(response.headers["Location"]).to eq("/dav/")
    end

    it "PROPFIND /.well-known/carddav also redirects" do
      process(:propfind, "/.well-known/carddav")
      expect(response).to have_http_status(301)
      expect(response.headers["Location"]).to eq("/dav/")
    end
  end

  describe "Step 1: Current-user-principal (RFC 5397)" do
    it "PROPFIND /dav/ returns current-user-principal for authenticated user" do
      dav_propfind "/dav/", user: user, depth: 0,
                   body: propfind_xml("current-user-principal")
      expect(response).to have_http_status(207)
      doc = parse_multistatus(response.body)
      principal = doc.at_xpath("//d:current-user-principal/d:href", NAMESPACES)
      expect(principal).to be_present
      expect(principal.text).to eq("/dav/alice/")
    end
  end

  describe "Step 2: Addressbook-home-set (RFC 6352 Section 7.1.1)" do
    it "PROPFIND on principal returns addressbook-home-set" do
      dav_propfind "/dav/alice/", user: user, depth: 0,
                   body: propfind_xml("card:addressbook-home-set")
      expect(response).to have_http_status(207)
      doc = parse_multistatus(response.body)
      home = doc.at_xpath("//card:addressbook-home-set/d:href", NAMESPACES)
      expect(home).to be_present
      expect(home.text).to eq("/dav/alice/contacts/")
    end
  end

  describe "Step 3: Addressbook collection listing" do
    it "PROPFIND on home-set with Depth:1 lists addressbooks" do
      dav_propfind "/dav/alice/contacts/", user: user, depth: 1,
                   body: propfind_xml("resourcetype", "displayname", "cs:getctag", "sync-token")
      expect(response).to have_http_status(207)
      doc = parse_multistatus(response.body)
      hrefs = extract_hrefs(doc)
      expect(hrefs).to include("/dav/alice/contacts/default/")
    end

    it "addressbook has resourcetype with both collection and addressbook" do
      dav_propfind "/dav/alice/contacts/", user: user, depth: 1,
                   body: propfind_xml("resourcetype")
      doc = parse_multistatus(response.body)
      ab_resp = find_response(doc, "/dav/alice/contacts/default/")
      expect(ab_resp).to be_present
      rt = ab_resp.at_xpath(".//d:resourcetype", NAMESPACES)
      expect(rt.at_xpath("d:collection", NAMESPACES)).to be_present
      expect(rt.at_xpath("card:addressbook", NAMESPACES)).to be_present
    end

    it "addressbook includes displayname" do
      dav_propfind "/dav/alice/contacts/", user: user, depth: 1,
                   body: propfind_xml("displayname")
      doc = parse_multistatus(response.body)
      ab_resp = find_response(doc, "/dav/alice/contacts/default/")
      dn = ab_resp.at_xpath(".//d:displayname", NAMESPACES)
      expect(dn.text).to eq("Contacts")
    end

    it "addressbook includes getctag in CalendarServer namespace" do
      dav_propfind "/dav/alice/contacts/", user: user, depth: 1,
                   body: propfind_xml("cs:getctag")
      doc = parse_multistatus(response.body)
      ab_resp = find_response(doc, "/dav/alice/contacts/default/")
      ctag = ab_resp.at_xpath(".//cs:getctag", NAMESPACES)
      expect(ctag).to be_present
      expect(ctag.text).to eq("0")
    end

    it "addressbook includes sync-token as a valid URI" do
      dav_propfind "/dav/alice/contacts/", user: user, depth: 1,
                   body: propfind_xml("sync-token")
      doc = parse_multistatus(response.body)
      ab_resp = find_response(doc, "/dav/alice/contacts/default/")
      st = ab_resp.at_xpath(".//d:sync-token", NAMESPACES)
      expect(st).to be_present
      expect(st.text).to match(%r{^http://.+/ns/sync/\d+$})
    end

    it "addressbook includes supported-report-set" do
      dav_propfind "/dav/alice/contacts/default/", user: user, depth: 0,
                   body: propfind_xml("supported-report-set")
      doc = parse_multistatus(response.body)
      srs = doc.at_xpath("//d:supported-report-set", NAMESPACES)
      expect(srs).to be_present
      reports = srs.xpath(".//d:report/*", NAMESPACES).map(&:name)
      expect(reports).to include("addressbook-multiget")
      expect(reports).to include("addressbook-query")
      expect(reports).to include("sync-collection")
    end
  end

  describe "Step 4: Addressbook properties" do
    it "returns supported-address-data with vCard 3.0 and 4.0" do
      dav_propfind "/dav/alice/contacts/default/", user: user, depth: 0,
                   body: propfind_xml("card:supported-address-data")
      doc = parse_multistatus(response.body)
      sad = doc.at_xpath("//card:supported-address-data", NAMESPACES)
      expect(sad).to be_present
      types = sad.xpath("card:address-data-type", NAMESPACES)
      versions = types.map { |t| t["version"] }
      expect(versions).to include("3.0")
      expect(versions).to include("4.0")
    end

    it "returns max-resource-size" do
      dav_propfind "/dav/alice/contacts/default/", user: user, depth: 0,
                   body: propfind_xml("card:max-resource-size")
      doc = parse_multistatus(response.body)
      mrs = doc.at_xpath("//card:max-resource-size", NAMESPACES)
      expect(mrs).to be_present
      expect(mrs.text.to_i).to be > 0
    end
  end
end
