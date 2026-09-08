require "rails_helper"

RSpec.describe "CardDAV per-addressbook DAV password", type: :request do
  let!(:user) { create(:user, username: "alice", password: "password123") }
  let(:book_a) { user.addressbooks.find_by(uri: "default") }
  let!(:book_b) { user.addressbooks.create!(uri: "work", displayname: "Work") }
  let(:password_a) { "password-alpha" }
  let(:password_b) { "password-bravo" }

  let!(:contact_a) do
    book_a.contacts.create!(
      uri: "alice-a.vcf",
      vcard_data: "BEGIN:VCARD\r\nVERSION:3.0\r\nUID:alice-a\r\nFN:Contact A\r\nEND:VCARD\r\n"
    )
  end

  let!(:contact_b) do
    book_b.contacts.create!(
      uri: "alice-b.vcf",
      vcard_data: "BEGIN:VCARD\r\nVERSION:3.0\r\nUID:alice-b\r\nFN:Contact B\r\nEND:VCARD\r\n"
    )
  end

  before do
    set_dav_password(book_a, password_a)
    set_dav_password(book_b, password_b)
  end

  it "rejects GET on another book with this book's password" do
    dav_get "/dav/alice/contacts/work/alice-b.vcf", user: user, password: password_a
    expect(response).to have_http_status(403)
  end

  it "rejects PUT on another book with this book's password" do
    vcard = "BEGIN:VCARD\r\nVERSION:3.0\r\nUID:sneak\r\nFN:Sneak\r\nEND:VCARD\r\n"
    dav_put "/dav/alice/contacts/work/sneak.vcf", body: vcard, user: user, password: password_a
    expect(response).to have_http_status(403)
    expect(book_b.contacts.find_by(uri: "sneak.vcf")).to be_nil
  end

  it "rejects DELETE on another book with this book's password" do
    dav_delete "/dav/alice/contacts/work/alice-b.vcf", user: user, password: password_a
    expect(response).to have_http_status(403)
    expect(book_b.contacts.find_by(uri: "alice-b.vcf")).to be_present
  end

  it "lists only authenticated books in home-set PROPFIND" do
    dav_propfind "/dav/alice/contacts/", user: user, password: password_a, depth: 1,
                 body: propfind_xml("displayname", "resourcetype")
    expect(response).to have_http_status(207)
    hrefs = extract_hrefs(parse_multistatus(response.body))
    expect(hrefs).to include("/dav/alice/contacts/default/")
    expect(hrefs).not_to include("/dav/alice/contacts/work/")
  end

  it "invalidates only the regenerated book's password" do
    book_a.regenerate_dav_password!

    dav_get "/dav/alice/contacts/default/alice-a.vcf", user: user, password: password_a
    expect(response).to have_http_status(401)

    dav_get "/dav/alice/contacts/work/alice-b.vcf", user: user, password: password_b
    expect(response).to have_http_status(200)
    expect(response.body).to include("Contact B")
  end
end
