module CardDav
  module Handlers
    class GetHandler
      include ResponseHelper

      def call(context)
        auth_error = authorize!(context)
        return auth_error if auth_error

        return method_not_allowed unless context.resource_type == :contact

        addressbook = find_addressbook(context)
        return not_found unless addressbook

        contact = find_contact(addressbook, context)
        return not_found unless contact

        if context.if_none_match&.include?(contact.etag)
          return empty_response(304, { "ETag" => contact.etag })
        end

        headers = {
          "Content-Type" => "text/vcard; charset=utf-8",
          "Content-Length" => contact.vcard_data.bytesize.to_s,
          "ETag" => contact.etag
        }

        body = context.method == "HEAD" ? [] : [contact.vcard_data]
        [200, headers, body]
      end
    end
  end
end
