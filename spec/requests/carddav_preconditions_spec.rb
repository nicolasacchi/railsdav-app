require "rails_helper"

RSpec.describe "CardDAV Preconditions", type: :request do
  let!(:user) { create(:user, username: "alice", password: "password123") }
  let(:ab) { user.addressbooks.first }
  let(:base) { "/dav/alice/contacts/default" }

  describe "UID conflict (RFC 6352 §6.3.2 no-uid-conflict)" do
    it "rejects new contact with duplicate UID" do
      vcard1 = "BEGIN:VCARD\r\nVERSION:3.0\r\nUID:dup-uid-1\r\nFN:First\r\nEND:VCARD\r\n"
      dav_put "#{base}/first.vcf", body: vcard1, user: user
      expect(response).to have_http_status(201)

      vcard2 = "BEGIN:VCARD\r\nVERSION:3.0\r\nUID:dup-uid-1\r\nFN:Duplicate\r\nEND:VCARD\r\n"
      dav_put "#{base}/second.vcf", body: vcard2, user: user
      expect(response).to have_http_status(409)
    end

    it "allows update to same resource with same UID" do
      vcard = "BEGIN:VCARD\r\nVERSION:3.0\r\nUID:same-uid\r\nFN:Original\r\nEND:VCARD\r\n"
      dav_put "#{base}/same.vcf", body: vcard, user: user
      expect(response).to have_http_status(201)
      etag = response.headers["ETag"]

      updated = "BEGIN:VCARD\r\nVERSION:3.0\r\nUID:same-uid\r\nFN:Updated\r\nEND:VCARD\r\n"
      dav_put "#{base}/same.vcf", body: updated, user: user, if_match: etag
      expect(response).to have_http_status(204)
    end

    it "allows new contact with unique UID" do
      vcard = "BEGIN:VCARD\r\nVERSION:3.0\r\nUID:unique-uid\r\nFN:New\r\nEND:VCARD\r\n"
      dav_put "#{base}/new.vcf", body: vcard, user: user
      expect(response).to have_http_status(201)
    end
  end

  describe "Content-Type validation" do
    it "accepts text/vcard" do
      vcard = "BEGIN:VCARD\r\nVERSION:3.0\r\nUID:ct-1\r\nFN:Test\r\nEND:VCARD\r\n"
      dav_put "#{base}/ct1.vcf", body: vcard, user: user, content_type: "text/vcard"
      expect(response).to have_http_status(201)
    end

    it "accepts text/vcard; charset=utf-8" do
      vcard = "BEGIN:VCARD\r\nVERSION:3.0\r\nUID:ct-2\r\nFN:Test\r\nEND:VCARD\r\n"
      dav_put "#{base}/ct2.vcf", body: vcard, user: user, content_type: "text/vcard; charset=utf-8"
      expect(response).to have_http_status(201)
    end

    it "rejects application/json" do
      vcard = "BEGIN:VCARD\r\nVERSION:3.0\r\nUID:ct-3\r\nFN:Test\r\nEND:VCARD\r\n"
      dav_put "#{base}/ct3.vcf", body: vcard, user: user, content_type: "application/json"
      expect(response).to have_http_status(415)
    end

    it "accepts text/x-vcard (legacy alias)" do
      vcard = "BEGIN:VCARD\r\nVERSION:3.0\r\nUID:ct-4\r\nFN:Test\r\nEND:VCARD\r\n"
      dav_put "#{base}/ct4.vcf", body: vcard, user: user, content_type: "text/x-vcard"
      expect(response).to have_http_status(201)
    end
  end

  describe "If-Match / If-None-Match edge cases" do
    it "PUT with multiple ETags in If-Match succeeds if one matches" do
      vcard = "BEGIN:VCARD\r\nVERSION:3.0\r\nUID:multi-etag\r\nFN:Multi\r\nEND:VCARD\r\n"
      dav_put "#{base}/multi.vcf", body: vcard, user: user
      etag = response.headers["ETag"]

      updated = "BEGIN:VCARD\r\nVERSION:3.0\r\nUID:multi-etag\r\nFN:Updated\r\nEND:VCARD\r\n"
      dav_put "#{base}/multi.vcf", body: updated, user: user, if_match: "\"wrong\", #{etag}, \"also-wrong\""
      expect(response).to have_http_status(204)
    end

    it "DELETE with If-Match: * succeeds" do
      vcard = "BEGIN:VCARD\r\nVERSION:3.0\r\nUID:star-del\r\nFN:Star\r\nEND:VCARD\r\n"
      dav_put "#{base}/star.vcf", body: vcard, user: user
      expect(response).to have_http_status(201)

      dav_delete "#{base}/star.vcf", user: user, if_match: "*"
      expect(response).to have_http_status(204)
    end

    it "GET with multiple ETags in If-None-Match returns 304 if any match" do
      vcard = "BEGIN:VCARD\r\nVERSION:3.0\r\nUID:inm-multi\r\nFN:INM\r\nEND:VCARD\r\n"
      dav_put "#{base}/inm.vcf", body: vcard, user: user
      etag = response.headers["ETag"]

      dav_get "#{base}/inm.vcf", user: user, if_none_match: "\"wrong\", #{etag}"
      expect(response).to have_http_status(304)
    end
  end
end
