require "rails_helper"

RSpec.describe "Authentication & Authorization", type: :request do
  let!(:user) { create(:user, username: "alice", password: "password123") }
  let!(:other_user) { create(:user, username: "bob", password: "password456") }

  describe "unauthenticated requests" do
    it "returns 401 with WWW-Authenticate header for PROPFIND without credentials" do
      process(:propfind, "/dav/", headers: { "HTTP_DEPTH" => "0" })
      expect(response).to have_http_status(401)
      expect(response.headers["WWW-Authenticate"]).to include("Basic")
    end

    it "returns 401 for GET without credentials" do
      process(:get, "/dav/alice/contacts/default/test.vcf")
      expect(response).to have_http_status(401)
    end

    it "returns 401 for OPTIONS without credentials" do
      process(:options, "/dav/alice/contacts/default/")
      expect(response).to have_http_status(401)
    end
  end

  describe "invalid credentials" do
    it "returns 401 for wrong password" do
      dav_propfind "/dav/", user: user, password: "wrongpassword", depth: 0
      expect(response).to have_http_status(401)
    end

    it "returns 401 for non-existent username" do
      headers = basic_auth_header("nonexistent", "password123")
      headers["HTTP_DEPTH"] = "0"
      process(:propfind, "/dav/", headers: headers)
      expect(response).to have_http_status(401)
    end
  end

  describe "authorization" do
    it "returns 403 when user A tries to access user B's resources" do
      dav_propfind "/dav/bob/", user: user, depth: 0,
                   body: propfind_xml("displayname")
      expect(response).to have_http_status(403)
    end

    it "allows user to access their own resources" do
      dav_propfind "/dav/alice/", user: user, depth: 0,
                   body: propfind_xml("displayname")
      expect(response).to have_http_status(207)
    end

    it "allows any authenticated user to access /dav/ root" do
      dav_propfind "/dav/", user: user, depth: 0,
                   body: propfind_xml("current-user-principal")
      expect(response).to have_http_status(207)
    end
  end

  describe "DAV password authentication" do
    it "authenticates with addressbook DAV password" do
      ab = user.addressbooks.first
      dav_propfind "/dav/alice/", user: user, password: ab.dav_password, depth: 0,
                   body: propfind_xml("displayname")
      expect(response).to have_http_status(207)
    end

    it "authenticates with email and DAV password" do
      ab = user.addressbooks.first
      headers = basic_auth_header(user.email, ab.dav_password)
      headers["HTTP_DEPTH"] = "0"
      process(:propfind, "/dav/alice/", headers: headers, params: propfind_xml("displayname"))
      expect(response).to have_http_status(207)
    end

    it "rejects wrong DAV password" do
      dav_propfind "/dav/alice/", user: user, password: "wrong-dav-password", depth: 0
      expect(response).to have_http_status(401)
    end

    it "rejects main password for DAV auth" do
      dav_propfind "/dav/alice/", user: user, password: "password123", depth: 0,
                   body: propfind_xml("displayname")
      expect(response).to have_http_status(401)
    end
  end

  describe ".well-known redirect" do
    it "redirects without requiring authentication" do
      get "/.well-known/carddav"
      expect(response).to have_http_status(301)
      expect(response.headers["Location"]).to eq("/dav/")
    end

    it "redirects PROPFIND on .well-known too" do
      process(:propfind, "/.well-known/carddav")
      expect(response).to have_http_status(301)
      expect(response.headers["Location"]).to eq("/dav/")
    end
  end
end
