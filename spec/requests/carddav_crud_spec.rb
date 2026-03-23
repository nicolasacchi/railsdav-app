require "rails_helper"

RSpec.describe "CardDAV vCard CRUD", type: :request do
  let!(:user) { create(:user, username: "alice", password: "password123") }
  let(:addressbook) { user.addressbooks.find_by(uri: "default") }

  let(:minimal_vcard) do
    "BEGIN:VCARD\r\nVERSION:3.0\r\nUID:minimal-001\r\nFN:Minimal Contact\r\nN:Contact;Minimal;;;\r\nEND:VCARD\r\n"
  end

  let(:rich_vcard) do
    <<~VCARD
      BEGIN:VCARD
      VERSION:3.0
      UID:rich-001
      FN:Jane Smith
      N:Smith;Jane;Marie;;Dr.
      EMAIL;TYPE=WORK:jane@work.com
      EMAIL;TYPE=HOME:jane@home.com
      TEL;TYPE=CELL:+1-555-0100
      TEL;TYPE=WORK:+1-555-0200
      ADR;TYPE=HOME:;;123 Main St;Springfield;IL;62701;US
      ORG:Acme Corp
      TITLE:Engineer
      NOTE:A test contact with many fields
      X-CUSTOM-PROPERTY:custom-value
      END:VCARD
    VCARD
  end

  let(:unicode_vcard) do
    "BEGIN:VCARD\r\nVERSION:3.0\r\nUID:unicode-001\r\nFN:\u7530\u4E2D\u592A\u90CE\r\nN:\u7530\u4E2D;\u592A\u90CE;;;\r\nNOTE:\u{1F600} emoji test \u0645\u0631\u062D\u0628\u0627\r\nEND:VCARD\r\n"
  end

  let(:vcard_v4) do
    "BEGIN:VCARD\r\nVERSION:4.0\r\nUID:v4-001\r\nFN:Version Four Contact\r\nEND:VCARD\r\n"
  end

  describe "Create (PUT)" do
    it "stores a minimal vCard" do
      dav_put "/dav/alice/contacts/default/minimal.vcf", body: minimal_vcard, user: user
      expect(response).to have_http_status(201)
      expect(response.headers["ETag"]).to be_present
    end

    it "stores a rich vCard with multiple properties" do
      dav_put "/dav/alice/contacts/default/rich.vcf", body: rich_vcard, user: user
      expect(response).to have_http_status(201)
    end

    it "stores a vCard with non-ASCII characters" do
      dav_put "/dav/alice/contacts/default/unicode.vcf", body: unicode_vcard, user: user
      expect(response).to have_http_status(201)
    end

    it "stores a vCard 4.0" do
      dav_put "/dav/alice/contacts/default/v4.vcf", body: vcard_v4, user: user
      expect(response).to have_http_status(201)
    end

    it "increments CTag on the addressbook" do
      expect {
        dav_put "/dav/alice/contacts/default/minimal.vcf", body: minimal_vcard, user: user
      }.to change { addressbook.reload.ctag }.by(1)
    end

    it "increments sync_token on the addressbook" do
      expect {
        dav_put "/dav/alice/contacts/default/minimal.vcf", body: minimal_vcard, user: user
      }.to change { addressbook.reload.sync_token }.by(1)
    end

    it "creates a sync_change record with type 'created'" do
      expect {
        dav_put "/dav/alice/contacts/default/minimal.vcf", body: minimal_vcard, user: user
      }.to change(SyncChange, :count).by(1)
      sc = SyncChange.last
      expect(sc.change_type).to eq("created")
      expect(sc.uri).to eq("minimal.vcf")
    end
  end

  describe "Read (GET)" do
    it "returns byte-identical body for minimal vCard" do
      dav_put "/dav/alice/contacts/default/minimal.vcf", body: minimal_vcard, user: user
      dav_get "/dav/alice/contacts/default/minimal.vcf", user: user
      expect(response.body).to eq(minimal_vcard)
    end

    it "returns byte-identical body for rich vCard with X-properties" do
      dav_put "/dav/alice/contacts/default/rich.vcf", body: rich_vcard, user: user
      dav_get "/dav/alice/contacts/default/rich.vcf", user: user
      expect(response.body).to eq(rich_vcard)
    end

    it "preserves non-ASCII characters" do
      dav_put "/dav/alice/contacts/default/unicode.vcf", body: unicode_vcard, user: user
      dav_get "/dav/alice/contacts/default/unicode.vcf", user: user
      expect(response.body).to eq(unicode_vcard)
    end

    it "returns Content-Type text/vcard; charset=utf-8" do
      dav_put "/dav/alice/contacts/default/minimal.vcf", body: minimal_vcard, user: user
      dav_get "/dav/alice/contacts/default/minimal.vcf", user: user
      expect(response.headers["Content-Type"]).to include("text/vcard")
    end
  end

  describe "Update (PUT)" do
    before do
      dav_put "/dav/alice/contacts/default/rich.vcf", body: rich_vcard, user: user
      @original_etag = response.headers["ETag"]
    end

    let(:updated_vcard) do
      rich_vcard.sub("Jane Smith", "Jane M. Smith")
    end

    it "returns 204 with new ETag" do
      dav_put "/dav/alice/contacts/default/rich.vcf", body: updated_vcard, user: user, if_match: @original_etag
      expect(response).to have_http_status(204)
      expect(response.headers["ETag"]).to be_present
      expect(response.headers["ETag"]).not_to eq(@original_etag)
    end

    it "fully replaces the vCard data" do
      dav_put "/dav/alice/contacts/default/rich.vcf", body: updated_vcard, user: user, if_match: @original_etag
      dav_get "/dav/alice/contacts/default/rich.vcf", user: user
      expect(response.body).to eq(updated_vcard)
    end

    it "increments CTag" do
      expect {
        dav_put "/dav/alice/contacts/default/rich.vcf", body: updated_vcard, user: user, if_match: @original_etag
      }.to change { addressbook.reload.ctag }.by(1)
    end

    it "creates a sync_change with type 'modified'" do
      dav_put "/dav/alice/contacts/default/rich.vcf", body: updated_vcard, user: user, if_match: @original_etag
      sc = SyncChange.where(change_type: "modified").last
      expect(sc).to be_present
      expect(sc.uri).to eq("rich.vcf")
    end
  end

  describe "Delete" do
    before do
      dav_put "/dav/alice/contacts/default/minimal.vcf", body: minimal_vcard, user: user
    end

    it "returns 204" do
      dav_delete "/dav/alice/contacts/default/minimal.vcf", user: user
      expect(response).to have_http_status(204)
    end

    it "increments CTag" do
      expect {
        dav_delete "/dav/alice/contacts/default/minimal.vcf", user: user
      }.to change { addressbook.reload.ctag }.by(1)
    end

    it "creates a sync_change with type 'deleted'" do
      dav_delete "/dav/alice/contacts/default/minimal.vcf", user: user
      sc = SyncChange.where(change_type: "deleted").last
      expect(sc).to be_present
      expect(sc.uri).to eq("minimal.vcf")
    end

    it "makes subsequent GET return 404" do
      dav_delete "/dav/alice/contacts/default/minimal.vcf", user: user
      dav_get "/dav/alice/contacts/default/minimal.vcf", user: user
      expect(response).to have_http_status(404)
    end
  end

  describe "Data integrity" do
    it "preserves unusual line folding" do
      folded = "BEGIN:VCARD\r\nVERSION:3.0\r\nUID:folded-001\r\nFN:A very long name that might get\r\n  folded across multiple lines\r\nEND:VCARD\r\n"
      dav_put "/dav/alice/contacts/default/folded.vcf", body: folded, user: user
      dav_get "/dav/alice/contacts/default/folded.vcf", user: user
      expect(response.body).to eq(folded)
    end

    it "preserves X-CUSTOM-PROPERTY" do
      dav_put "/dav/alice/contacts/default/rich.vcf", body: rich_vcard, user: user
      dav_get "/dav/alice/contacts/default/rich.vcf", user: user
      expect(response.body).to include("X-CUSTOM-PROPERTY:custom-value")
    end
  end
end
