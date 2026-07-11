require "rails_helper"

# Regression coverage for the XXE fix: the CardDAV XML parser must not expand
# external entities, so a REPORT body referencing a local file can't disclose it.
RSpec.describe "CardDAV XXE hardening", type: :request do
  include DavHelpers

  let(:user) { create(:user, username: "victim") }
  # The user factory already creates a "default" addressbook; reuse it.
  let(:addressbook) { user.addressbooks.find_by!(uri: "default") }

  it "does not expand a file:// external entity in a multiget REPORT" do
    sentinel = "TOP-SECRET-#{SecureRandom.hex(8)}"
    secret_file = Rails.root.join("tmp", "xxe_secret_#{SecureRandom.hex(4)}.txt")
    File.write(secret_file, sentinel)

    begin
      body = <<~XML
        <?xml version="1.0"?>
        <!DOCTYPE r [<!ENTITY xxe SYSTEM "file://#{secret_file}">]>
        <card:addressbook-multiget xmlns:card="urn:ietf:params:xml:ns:carddav" xmlns:d="DAV:">
          <d:prop><d:getetag/></d:prop>
          <d:href>&xxe;</d:href>
        </card:addressbook-multiget>
      XML

      dav_report("/dav/#{user.username}/contacts/#{addressbook.uri}/", body: body, user: user)

      expect(response.body).not_to include(sentinel)
    ensure
      File.delete(secret_file) if File.exist?(secret_file)
    end
  end
end
