require "rails_helper"

RSpec.describe "WebDAV Sharing", type: :request do
  let!(:owner) { create(:user, username: "alice", password: "password123") }
  let!(:shared_user) { create(:user, username: "bob", password: "password123") }
  let(:addressbook) { owner.addressbooks.find_by(uri: "default") }
  let!(:contact) do
    addressbook.contacts.create!(
      uri: "shared-contact.vcf",
      vcard_data: "BEGIN:VCARD\r\nVERSION:3.0\r\nUID:shared-uid\r\nFN:Shared Contact\r\nEND:VCARD\r\n"
    )
  end

  describe "Private sharing (read-only)" do
    before do
      create(:addressbook_share, addressbook: addressbook, user: shared_user, permission: "read")
    end

    it "allows PROPFIND on shared addressbook" do
      dav_propfind "/dav/alice/contacts/default/", user: shared_user,
        body: propfind_xml("displayname", "resourcetype")
      expect(response).to have_http_status(207)
    end

    it "allows GET on shared contact" do
      dav_get "/dav/alice/contacts/default/shared-contact.vcf", user: shared_user
      expect(response).to have_http_status(200)
      expect(response.body).to include("Shared Contact")
    end

    it "blocks PUT on read-only share" do
      vcard = "BEGIN:VCARD\r\nVERSION:3.0\r\nUID:new-uid\r\nFN:New\r\nEND:VCARD\r\n"
      dav_put "/dav/alice/contacts/default/new.vcf", body: vcard, user: shared_user
      expect(response).to have_http_status(403)
    end

    it "blocks DELETE on read-only share" do
      dav_delete "/dav/alice/contacts/default/shared-contact.vcf", user: shared_user
      expect(response).to have_http_status(403)
    end

    it "returns read-only privileges" do
      dav_propfind "/dav/alice/contacts/default/", user: shared_user,
        body: propfind_xml("current-user-privilege-set")
      doc = parse_multistatus(response.body)
      privileges = doc.xpath("//d:current-user-privilege-set/d:privilege/*", NAMESPACES).map(&:name)
      expect(privileges).to include("read")
      expect(privileges).not_to include("write")
    end
  end

  describe "Private sharing (read-write)" do
    before do
      create(:addressbook_share, addressbook: addressbook, user: shared_user, permission: "write")
    end

    it "allows PUT on writable share" do
      vcard = "BEGIN:VCARD\r\nVERSION:3.0\r\nUID:new-uid\r\nFN:New Contact\r\nEND:VCARD\r\n"
      dav_put "/dav/alice/contacts/default/new.vcf", body: vcard, user: shared_user
      expect(response).to have_http_status(201)
    end

    it "allows DELETE on writable share" do
      dav_delete "/dav/alice/contacts/default/shared-contact.vcf", user: shared_user, if_match: contact.etag
      expect(response).to have_http_status(204)
    end

    it "blocks DELETE of the collection for a write share" do
      dav_delete "/dav/alice/contacts/default/", user: shared_user
      expect(response).to have_http_status(403)
      expect(Addressbook.exists?(addressbook.id)).to be true
    end

    it "blocks PROPPATCH displayname on the collection for a write share" do
      xml = <<~XML
        <?xml version="1.0" encoding="utf-8"?>
        <d:propertyupdate xmlns:d="DAV:">
          <d:set><d:prop>
            <d:displayname>Hijacked</d:displayname>
          </d:prop></d:set>
        </d:propertyupdate>
      XML
      headers = { "CONTENT_TYPE" => "application/xml; charset=utf-8" }
      headers.merge!(basic_auth_header(shared_user.username, DAV_TEST_PASSWORD))
      process(:proppatch, "/dav/alice/contacts/default/", headers: headers, params: xml)
      expect(response).to have_http_status(403)
      expect(addressbook.reload.displayname).not_to eq("Hijacked")
    end
  end

  describe "Shared addressbook discovery" do
    before do
      create(:addressbook_share, addressbook: addressbook, user: shared_user, permission: "read")
    end

    it "includes shared addressbooks in home-set PROPFIND" do
      dav_propfind "/dav/bob/contacts/", user: shared_user, depth: 1,
        body: propfind_xml("displayname", "resourcetype")
      doc = parse_multistatus(response.body)
      hrefs = extract_hrefs(doc)
      expect(hrefs).to include("/dav/alice/contacts/default/")
    end
  end

  describe "No share" do
    it "blocks access to another user's addressbook" do
      dav_propfind "/dav/alice/contacts/default/", user: shared_user,
        body: propfind_xml("displayname")
      expect(response).to have_http_status(403)
    end

    it "blocks GET on another user's contact" do
      dav_get "/dav/alice/contacts/default/shared-contact.vcf", user: shared_user
      expect(response).to have_http_status(403)
    end
  end

  describe "Owner collection admin" do
    it "allows the owner to DELETE the collection" do
      dav_delete "/dav/alice/contacts/default/", user: owner
      expect(response).to have_http_status(204)
      expect(owner.addressbooks.find_by(uri: "default")).to be_nil
    end
  end

  describe "Public CardDAV endpoint" do
    let!(:public_share) { create(:addressbook_share, :public_link, addressbook: addressbook) }

    it "allows PROPFIND without auth" do
      dav_propfind "/dav/public/#{public_share.token}/",
        body: propfind_xml("displayname", "resourcetype")
      expect(response).to have_http_status(207)
    end

    it "allows GET on contact without auth" do
      dav_get "/dav/public/#{public_share.token}/shared-contact.vcf"
      expect(response).to have_http_status(200)
      expect(response.body).to include("Shared Contact")
    end

    it "blocks PUT on public endpoint" do
      vcard = "BEGIN:VCARD\r\nVERSION:3.0\r\nUID:new\r\nFN:New\r\nEND:VCARD\r\n"
      dav_put "/dav/public/#{public_share.token}/new.vcf", body: vcard
      expect(response).to have_http_status(403)
    end

    it "blocks DELETE on public endpoint" do
      dav_delete "/dav/public/#{public_share.token}/shared-contact.vcf"
      expect(response).to have_http_status(403)
    end

    it "returns 404 for invalid token" do
      dav_propfind "/dav/public/invalid-token/",
        body: propfind_xml("displayname")
      expect(response).to have_http_status(404)
    end

    it "returns read-only privileges" do
      dav_propfind "/dav/public/#{public_share.token}/",
        body: propfind_xml("current-user-privilege-set")
      doc = parse_multistatus(response.body)
      privileges = doc.xpath("//d:current-user-privilege-set/d:privilege/*", NAMESPACES).map(&:name)
      expect(privileges).to include("read")
      expect(privileges).not_to include("write")
    end
  end
end
