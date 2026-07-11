module CardDav
  module Handlers
    class MkcolHandler
      include ResponseHelper

      def call(context)
        auth_error = authorize!(context)
        return auth_error if auth_error

        write_error = require_writable!(context)
        return write_error if write_error

        return method_not_allowed unless context.resource_type == :addressbook

        uri = context.addressbook_uri
        return bad_request("Invalid addressbook URI") unless uri

        if context.user.addressbooks.exists?(uri: uri)
          return text_response(409, "Addressbook already exists")
        end

        displayname = uri.capitalize
        description = nil

        if context.body && !context.body.strip.empty?
          doc = Nokogiri::XML(context.body) { |config| config.nonet }
          ns = Xml::NAMESPACES
          dn = doc.at_xpath("//d:displayname", ns)
          displayname = dn.text if dn
          desc = doc.at_xpath("//card:addressbook-description", ns)
          description = desc.text if desc
        end

        context.user.addressbooks.create!(
          uri: uri,
          displayname: displayname,
          description: description
        )

        empty_response(201)
      end
    end
  end
end
