require "rails_helper"

RSpec.describe "WebDAV Foundation", type: :request do
  let!(:user) { create(:user, username: "alice", password: "password123") }
  let(:addressbook) { user.addressbooks.find_by(uri: "default") }

  let(:vcard) do
    <<~VCARD
      BEGIN:VCARD
      VERSION:3.0
      UID:test-uid-001
      FN:John Doe
      N:Doe;John;;;
      EMAIL:john@example.com
      END:VCARD
    VCARD
  end

  describe "OPTIONS" do
    it "returns 200 with DAV compliance header" do
      dav_options "/dav/alice/contacts/default/", user: user
      expect(response).to have_http_status(200)
      expect(response.headers["DAV"]).to eq("1, 2, 3, addressbook")
    end

    it "returns Allow header with supported methods" do
      dav_options "/dav/alice/contacts/default/", user: user
      allow = response.headers["Allow"]
      %w[OPTIONS GET HEAD PUT DELETE PROPFIND PROPPATCH REPORT MKCOL].each do |method|
        expect(allow).to include(method)
      end
    end
  end

  describe "PUT a vCard" do
    it "creates a new contact and returns 201 with ETag" do
      dav_put "/dav/alice/contacts/default/john.vcf", body: vcard, user: user
      expect(response).to have_http_status(201)
      expect(response.headers["ETag"]).to be_present
      expect(response.headers["ETag"]).to match(/^"[a-f0-9]{64}"$/)
    end

    it "computes ETag as quoted SHA-256 of body" do
      dav_put "/dav/alice/contacts/default/john.vcf", body: vcard, user: user
      expected_etag = "\"#{Digest::SHA256.hexdigest(vcard)}\""
      expect(response.headers["ETag"]).to eq(expected_etag)
    end

    it "rejects PUT without UID in vCard" do
      bad_vcard = "BEGIN:VCARD\nVERSION:3.0\nFN:No UID\nEND:VCARD"
      dav_put "/dav/alice/contacts/default/noid.vcf", body: bad_vcard, user: user
      expect(response).to have_http_status(400)
    end

    it "rejects PUT to a collection URI" do
      dav_put "/dav/alice/contacts/default/", body: vcard, user: user
      expect(response).to have_http_status(409)
    end
  end

  describe "GET a vCard" do
    before do
      dav_put "/dav/alice/contacts/default/john.vcf", body: vcard, user: user
    end

    it "returns 200 with the vCard body" do
      dav_get "/dav/alice/contacts/default/john.vcf", user: user
      expect(response).to have_http_status(200)
      expect(response.body).to eq(vcard)
    end

    it "returns correct Content-Type" do
      dav_get "/dav/alice/contacts/default/john.vcf", user: user
      expect(response.headers["Content-Type"]).to include("text/vcard")
    end

    it "returns matching ETag header" do
      dav_get "/dav/alice/contacts/default/john.vcf", user: user
      expected_etag = "\"#{Digest::SHA256.hexdigest(vcard)}\""
      expect(response.headers["ETag"]).to eq(expected_etag)
    end

    it "returns 404 for non-existent resource" do
      dav_get "/dav/alice/contacts/default/nonexistent.vcf", user: user
      expect(response).to have_http_status(404)
    end
  end

  describe "DELETE a vCard" do
    before do
      dav_put "/dav/alice/contacts/default/john.vcf", body: vcard, user: user
    end

    it "returns 204" do
      dav_delete "/dav/alice/contacts/default/john.vcf", user: user
      expect(response).to have_http_status(204)
    end

    it "makes subsequent GET return 404" do
      dav_delete "/dav/alice/contacts/default/john.vcf", user: user
      dav_get "/dav/alice/contacts/default/john.vcf", user: user
      expect(response).to have_http_status(404)
    end
  end

  describe "Conditional requests (If-Match)" do
    before do
      dav_put "/dav/alice/contacts/default/john.vcf", body: vcard, user: user
      @etag = response.headers["ETag"]
    end

    it "PUT with matching If-Match succeeds" do
      updated = vcard.sub("John Doe", "John M. Doe")
      dav_put "/dav/alice/contacts/default/john.vcf", body: updated, user: user, if_match: @etag
      expect(response).to have_http_status(204)
    end

    it "PUT with non-matching If-Match returns 412" do
      updated = vcard.sub("John Doe", "John M. Doe")
      dav_put "/dav/alice/contacts/default/john.vcf", body: updated, user: user, if_match: '"wrong-etag"'
      expect(response).to have_http_status(412)
    end

    it "DELETE with matching If-Match succeeds" do
      dav_delete "/dav/alice/contacts/default/john.vcf", user: user, if_match: @etag
      expect(response).to have_http_status(204)
    end

    it "DELETE with non-matching If-Match returns 412" do
      dav_delete "/dav/alice/contacts/default/john.vcf", user: user, if_match: '"wrong-etag"'
      expect(response).to have_http_status(412)
    end
  end

  describe "Conditional requests (If-None-Match)" do
    before do
      dav_put "/dav/alice/contacts/default/john.vcf", body: vcard, user: user
      @etag = response.headers["ETag"]
    end

    it "PUT with If-None-Match: * on existing resource returns 412" do
      updated = vcard.sub("John Doe", "John M. Doe")
      dav_put "/dav/alice/contacts/default/john.vcf", body: updated, user: user, if_none_match: "*"
      expect(response).to have_http_status(412)
    end

    it "PUT with If-None-Match: * on new resource succeeds" do
      new_vcard = simple_vcard(uid: "new-uid", fn: "New Person")
      dav_put "/dav/alice/contacts/default/new.vcf", body: new_vcard, user: user, if_none_match: "*"
      expect(response).to have_http_status(201)
    end

    it "GET with matching If-None-Match returns 304" do
      dav_get "/dav/alice/contacts/default/john.vcf", user: user, if_none_match: @etag
      expect(response).to have_http_status(304)
    end
  end

  describe "PROPFIND on collection (Depth: 0)" do
    it "returns 207 Multi-Status" do
      dav_propfind "/dav/alice/contacts/default/", user: user, depth: 0,
                   body: propfind_xml("displayname", "resourcetype")
      expect(response).to have_http_status(207)
    end

    it "returns valid XML with multistatus root" do
      dav_propfind "/dav/alice/contacts/default/", user: user, depth: 0,
                   body: propfind_xml("displayname")
      doc = parse_multistatus(response.body)
      expect(doc.root.name).to eq("multistatus")
    end

    it "contains response with correct href" do
      dav_propfind "/dav/alice/contacts/default/", user: user, depth: 0,
                   body: propfind_xml("displayname")
      doc = parse_multistatus(response.body)
      hrefs = extract_hrefs(doc)
      expect(hrefs).to include("/dav/alice/contacts/default/")
    end

    it "returns Content-Type application/xml" do
      dav_propfind "/dav/alice/contacts/default/", user: user, depth: 0,
                   body: propfind_xml("displayname")
      expect(response.headers["Content-Type"]).to include("application/xml")
    end
  end

  describe "PROPFIND on collection (Depth: 1)" do
    before do
      dav_put "/dav/alice/contacts/default/john.vcf", body: vcard, user: user
    end

    it "returns responses for collection and children" do
      dav_propfind "/dav/alice/contacts/default/", user: user, depth: 1,
                   body: propfind_xml("getetag", "getcontenttype")
      expect(response).to have_http_status(207)
      doc = parse_multistatus(response.body)
      hrefs = extract_hrefs(doc)
      expect(hrefs).to include("/dav/alice/contacts/default/")
      expect(hrefs).to include("/dav/alice/contacts/default/john.vcf")
    end

    it "includes getetag for each child resource" do
      dav_propfind "/dav/alice/contacts/default/", user: user, depth: 1,
                   body: propfind_xml("getetag")
      doc = parse_multistatus(response.body)
      contact_resp = find_response(doc, "/dav/alice/contacts/default/john.vcf")
      expect(contact_resp).to be_present
      etag = contact_resp.at_xpath(".//d:getetag", NAMESPACES)
      expect(etag).to be_present
    end
  end

  describe "Error cases" do
    it "returns 401 for unauthenticated DAV requests" do
      process(:propfind, "/dav/alice/contacts/default/", headers: { "HTTP_DEPTH" => "0" })
      expect(response).to have_http_status(401)
    end

    it "returns 403 when user A accesses user B's resources" do
      other = create(:user, username: "bob", password: "password123")
      dav_get "/dav/bob/contacts/default/test.vcf", user: user
      expect(response).to have_http_status(403)
    end

    it "returns 403 for PROPFIND with Depth: infinity" do
      dav_propfind "/dav/alice/contacts/default/", user: user, depth: "infinity",
                   body: propfind_xml("displayname")
      expect(response).to have_http_status(403)
    end
  end
end
