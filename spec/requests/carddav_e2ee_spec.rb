require "rails_helper"

RSpec.describe "CardDAV E2EE Support", type: :request do
  let!(:user) { create(:user, username: "alice", password: "password123") }
  let(:ab) { user.addressbooks.first }
  let(:base) { "/dav/alice/contacts/default" }

  let(:encrypted_blob) { SecureRandom.random_bytes(256) }
  let(:bootstrap_vcard) do
    "BEGIN:VCARD\r\nVERSION:3.0\r\nUID:system-bootstrap@e2e-carddav\r\n" \
    "FN:E2EE Bootstrap\r\nCATEGORIES:SYSTEM,BOOTSTRAP\r\n" \
    "X-E2EE-ALGORITHM:xchacha20-poly1305-v1\r\nX-E2EE-KDF:argon2id\r\n" \
    "X-E2EE-SALT:dGVzdHNhbHQ=\r\nX-E2EE-VERSION:1\r\nEND:VCARD\r\n"
  end

  describe "PUT encrypted contact" do
    it "stores an encrypted blob and returns 201" do
      dav_put "#{base}/enc1.vcf", body: encrypted_blob, user: user,
              content_type: "application/octet-stream",
              headers: { "HTTP_X_E2EE_UID" => "enc-uid-001" }
      expect(response).to have_http_status(201)
      expect(response.headers["ETag"]).to be_present
    end

    it "marks the contact as encrypted" do
      dav_put "#{base}/enc1.vcf", body: encrypted_blob, user: user,
              content_type: "application/octet-stream",
              headers: { "HTTP_X_E2EE_UID" => "enc-uid-001" }
      contact = ab.contacts.find_by(uri: "enc1.vcf")
      expect(contact.encrypted?).to be true
      expect(contact.uid).to eq("enc-uid-001")
    end

    it "sets cached_display_name to [Encrypted]" do
      dav_put "#{base}/enc1.vcf", body: encrypted_blob, user: user,
              content_type: "application/octet-stream",
              headers: { "HTTP_X_E2EE_UID" => "enc-uid-001" }
      contact = ab.contacts.find_by(uri: "enc1.vcf")
      expect(contact.cached_display_name).to eq("[Encrypted]")
    end

    it "falls back to URI-derived UID when no X-E2EE-UID header" do
      dav_put "#{base}/fallback-uid.vcf", body: encrypted_blob, user: user,
              content_type: "application/octet-stream"
      contact = ab.contacts.find_by(uri: "fallback-uid.vcf")
      expect(contact.uid).to eq("fallback-uid")
    end

    it "marks addressbook as encryption_enabled" do
      dav_put "#{base}/enc1.vcf", body: encrypted_blob, user: user,
              content_type: "application/octet-stream",
              headers: { "HTTP_X_E2EE_UID" => "enc-uid-001" }
      expect(ab.reload.encryption_enabled?).to be true
    end
  end

  describe "GET encrypted contact" do
    before do
      dav_put "#{base}/enc1.vcf", body: encrypted_blob, user: user,
              content_type: "application/octet-stream",
              headers: { "HTTP_X_E2EE_UID" => "enc-uid-001" }
    end

    it "returns the encrypted blob byte-identical" do
      dav_get "#{base}/enc1.vcf", user: user
      expect(response.body.b).to eq(encrypted_blob)
    end

    it "returns Content-Type application/octet-stream" do
      dav_get "#{base}/enc1.vcf", user: user
      expect(response.headers["Content-Type"]).to eq("application/octet-stream")
    end
  end

  describe "Bootstrap vCard" do
    it "stores bootstrap vCard as unencrypted" do
      dav_put "#{base}/system-bootstrap@e2e-carddav.vcf",
              body: bootstrap_vcard, user: user
      expect(response).to have_http_status(201)
      contact = ab.contacts.find_by(uid: "system-bootstrap@e2e-carddav")
      expect(contact.encrypted?).to be false
    end

    it "marks addressbook as encryption_enabled" do
      dav_put "#{base}/system-bootstrap@e2e-carddav.vcf",
              body: bootstrap_vcard, user: user
      expect(ab.reload.encryption_enabled?).to be true
    end

    it "does not create SYSTEM or BOOTSTRAP groups" do
      dav_put "#{base}/system-bootstrap@e2e-carddav.vcf",
              body: bootstrap_vcard, user: user
      expect(ab.contact_groups.pluck(:name)).not_to include("SYSTEM", "BOOTSTRAP")
    end

    it "clears encryption_enabled when bootstrap deleted and no encrypted contacts" do
      dav_put "#{base}/system-bootstrap@e2e-carddav.vcf",
              body: bootstrap_vcard, user: user
      expect(ab.reload.encryption_enabled?).to be true

      dav_delete "#{base}/system-bootstrap@e2e-carddav.vcf", user: user
      expect(ab.reload.encryption_enabled?).to be false
    end
  end

  describe "addressbook-query excludes encrypted" do
    before do
      dav_put "#{base}/plain.vcf",
              body: simple_vcard(uid: "plain-001", fn: "Alice Plain"), user: user
      dav_put "#{base}/enc1.vcf", body: encrypted_blob, user: user,
              content_type: "application/octet-stream",
              headers: { "HTTP_X_E2EE_UID" => "enc-uid-001" }
    end

    it "excludes encrypted contacts from text-match queries" do
      query_xml = <<~XML
        <?xml version="1.0" encoding="utf-8"?>
        <card:addressbook-query xmlns:d="DAV:" xmlns:card="urn:ietf:params:xml:ns:carddav">
          <d:prop><d:getetag/></d:prop>
          <card:filter><card:prop-filter name="FN">
            <card:text-match match-type="contains">Alice</card:text-match>
          </card:prop-filter></card:filter>
        </card:addressbook-query>
      XML
      dav_report "#{base}/", body: query_xml, user: user
      doc = parse_multistatus(response.body)
      hrefs = extract_hrefs(doc)
      expect(hrefs).to include(a_string_matching(/plain\.vcf/))
      expect(hrefs).not_to include(a_string_matching(/enc1\.vcf/))
    end

    it "includes encrypted contacts in unfiltered queries" do
      query_xml = <<~XML
        <?xml version="1.0" encoding="utf-8"?>
        <card:addressbook-query xmlns:d="DAV:" xmlns:card="urn:ietf:params:xml:ns:carddav">
          <d:prop><d:getetag/></d:prop>
          <card:filter/>
        </card:addressbook-query>
      XML
      dav_report "#{base}/", body: query_xml, user: user
      doc = parse_multistatus(response.body)
      hrefs = extract_hrefs(doc)
      expect(hrefs.size).to eq(2)
    end
  end

  describe "sync-collection includes encrypted" do
    it "returns both encrypted and unencrypted contacts" do
      dav_put "#{base}/plain.vcf",
              body: simple_vcard(uid: "plain-001"), user: user
      dav_put "#{base}/enc1.vcf", body: encrypted_blob, user: user,
              content_type: "application/octet-stream",
              headers: { "HTTP_X_E2EE_UID" => "enc-uid-001" }

      sync_xml = <<~XML
        <?xml version="1.0" encoding="utf-8"?>
        <d:sync-collection xmlns:d="DAV:">
          <d:sync-token/>
          <d:prop><d:getetag/></d:prop>
        </d:sync-collection>
      XML
      dav_report "#{base}/", body: sync_xml, user: user
      doc = parse_multistatus(response.body)
      hrefs = extract_hrefs(doc)
      expect(hrefs).to include(a_string_matching(/plain\.vcf/))
      expect(hrefs).to include(a_string_matching(/enc1\.vcf/))
    end
  end

  describe "mixed addressbook" do
    it "supports encrypted and unencrypted contacts together" do
      dav_put "#{base}/plain.vcf",
              body: simple_vcard(uid: "plain-001"), user: user
      dav_put "#{base}/enc1.vcf", body: encrypted_blob, user: user,
              content_type: "application/octet-stream",
              headers: { "HTTP_X_E2EE_UID" => "enc-uid-001" }

      expect(ab.contacts.count).to eq(2)
      expect(ab.contacts.encrypted.count).to eq(1)
      expect(ab.contacts.unencrypted.count).to eq(1)
    end
  end
end
