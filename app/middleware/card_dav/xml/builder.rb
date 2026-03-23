module CardDav
  module Xml
    DAV_NS = "DAV:".freeze
    CARDDAV_NS = "urn:ietf:params:xml:ns:carddav".freeze
    CALSERVER_NS = "http://calendarserver.org/ns/".freeze

    NAMESPACES = {
      "d" => DAV_NS,
      "card" => CARDDAV_NS,
      "cs" => CALSERVER_NS
    }.freeze
  end
end
