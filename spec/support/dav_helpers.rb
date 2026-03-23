DAV_NS = "DAV:".freeze
CARDDAV_NS = "urn:ietf:params:xml:ns:carddav".freeze
CALSERVER_NS = "http://calendarserver.org/ns/".freeze
NAMESPACES = {
  "d" => DAV_NS,
  "card" => CARDDAV_NS,
  "cs" => CALSERVER_NS
}.freeze

DAV_TEST_PASSWORD = "test-dav-password".freeze

module DavHelpers

  def basic_auth_header(username, password)
    { "HTTP_AUTHORIZATION" => ActionController::HttpAuthentication::Basic.encode_credentials(username, password) }
  end

  def set_dav_password(addressbook, password = DAV_TEST_PASSWORD)
    addressbook.update_column(:dav_password_digest, BCrypt::Password.create(password))
    password
  end

  def dav_password_for(user, password: DAV_TEST_PASSWORD)
    set_dav_password(user.addressbooks.first, password)
  end

  def dav_propfind(path, body: nil, depth: 0, user: nil, password: nil)
    headers = { "CONTENT_TYPE" => "application/xml; charset=utf-8", "HTTP_DEPTH" => depth.to_s }
    headers.merge!(basic_auth_header(user.username, password || DAV_TEST_PASSWORD)) if user
    process(:propfind, path, headers: headers, params: body)
  end

  def dav_report(path, body:, depth: 1, user: nil, password: nil)
    headers = { "CONTENT_TYPE" => "application/xml; charset=utf-8", "HTTP_DEPTH" => depth.to_s }
    headers.merge!(basic_auth_header(user.username, password || DAV_TEST_PASSWORD)) if user
    process(:report, path, headers: headers, params: body)
  end

  def dav_options(path, user: nil, password: nil)
    headers = {}
    headers.merge!(basic_auth_header(user.username, password || DAV_TEST_PASSWORD)) if user
    process(:options, path, headers: headers)
  end

  def dav_put(path, body:, user: nil, password: nil, content_type: "text/vcard; charset=utf-8", if_match: nil, if_none_match: nil)
    headers = { "CONTENT_TYPE" => content_type }
    headers.merge!(basic_auth_header(user.username, password || DAV_TEST_PASSWORD)) if user
    headers["HTTP_IF_MATCH"] = if_match if if_match
    headers["HTTP_IF_NONE_MATCH"] = if_none_match if if_none_match
    process(:put, path, headers: headers, params: body)
  end

  def dav_get(path, user: nil, password: nil, if_none_match: nil)
    headers = {}
    headers.merge!(basic_auth_header(user.username, password || DAV_TEST_PASSWORD)) if user
    headers["HTTP_IF_NONE_MATCH"] = if_none_match if if_none_match
    process(:get, path, headers: headers)
  end

  def dav_delete(path, user: nil, password: nil, if_match: nil)
    headers = {}
    headers.merge!(basic_auth_header(user.username, password || DAV_TEST_PASSWORD)) if user
    headers["HTTP_IF_MATCH"] = if_match if if_match
    process(:delete, path, headers: headers)
  end

  def dav_mkcol(path, body: nil, user: nil, password: nil)
    headers = { "CONTENT_TYPE" => "application/xml; charset=utf-8" }
    headers.merge!(basic_auth_header(user.username, password || DAV_TEST_PASSWORD)) if user
    process(:mkcol, path, headers: headers, params: body)
  end

  def parse_multistatus(body)
    Nokogiri::XML(body)
  end

  def extract_hrefs(doc)
    doc.xpath("//d:response/d:href", NAMESPACES).map(&:text)
  end

  def find_response(doc, href)
    doc.xpath("//d:response", NAMESPACES).find do |r|
      r.at_xpath("d:href", NAMESPACES)&.text == href
    end
  end

  def propfind_xml(*properties)
    props = properties.map do |p|
      case p
      when /^cs:/
        "<cs:#{p.sub('cs:', '')}/>"
      when /^card:/
        "<card:#{p.sub('card:', '')}/>"
      else
        "<d:#{p}/>"
      end
    end

    <<~XML
      <?xml version="1.0" encoding="utf-8"?>
      <d:propfind xmlns:d="DAV:" xmlns:card="urn:ietf:params:xml:ns:carddav" xmlns:cs="http://calendarserver.org/ns/">
        <d:prop>
          #{props.join("\n      ")}
        </d:prop>
      </d:propfind>
    XML
  end

  def simple_vcard(uid: "test-uid-001", fn: "Test Contact", version: "3.0")
    <<~VCARD
      BEGIN:VCARD
      VERSION:#{version}
      UID:#{uid}
      FN:#{fn}
      N:Contact;Test;;;
      END:VCARD
    VCARD
  end
end

RSpec.configure do |config|
  config.include DavHelpers, type: :request
end
