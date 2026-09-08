module CardDav
  module Handlers
    class ProppatchHandler
      include ResponseHelper

      def call(context)
        auth_error = authorize!(context)
        return auth_error if auth_error

        owner_error = require_owner!(context)
        return owner_error if owner_error

        return bad_request unless context.body
        return method_not_allowed unless context.resource_type == :addressbook

        addressbook = find_addressbook(context)
        return not_found unless addressbook

        doc = Nokogiri::XML(context.body) { |config| config.nonet }
        ns = Xml::NAMESPACES

        updates = {}
        doc.xpath("//d:set/d:prop/*", ns).each do |prop|
          case prop.name
          when "displayname"
            updates[:displayname] = prop.text
          end
        end

        addressbook.update!(updates) if updates.any?

        ms = Xml::MultiStatus.new
        href = "/dav/#{context.user.username}/contacts/#{addressbook.uri}/"
        ms.add_response(href: href) do |resp|
          updates.each_key do |key|
            resp.prop(Xml::DAV_NS, key.to_s)
          end
        end

        xml_response(207, ms.build)
      end
    end
  end
end
