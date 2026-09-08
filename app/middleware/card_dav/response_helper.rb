require "erb"
require "cgi"

module CardDav
  module ResponseHelper
    # Percent-encode a resource name for use as a URL path segment. Emits %20 for
    # spaces (not "+") so the href is a valid RFC 3986 URI reference that clients
    # can echo back and we can decode symmetrically. Safe URIs (UUID.vcf) are
    # unchanged. Contact URIs are CGI.unescaped on the way in (RequestContext),
    # so they must be re-encoded here to round-trip.
    def encode_uri_segment(segment)
      ERB::Util.url_encode(segment.to_s)
    end

    # Inverse of the request path decoding in RequestContext#path_segments, so a
    # multiget href resolves to the same stored uri regardless of escaping.
    def decode_uri_segment(segment)
      CGI.unescape(segment.to_s)
    end

    def xml_response(status, body)
      [status, {
        "Content-Type" => "application/xml; charset=utf-8",
        "Content-Length" => body.bytesize.to_s
      }, [body]]
    end

    def text_response(status, body)
      [status, {
        "Content-Type" => "text/plain",
        "Content-Length" => body.bytesize.to_s
      }, [body]]
    end

    def empty_response(status, headers = {})
      [status, { "Content-Length" => "0" }.merge(headers), []]
    end

    def not_found
      text_response(404, "Not Found")
    end

    def forbidden(body = "Forbidden")
      text_response(403, body)
    end

    def precondition_failed
      text_response(412, "Precondition Failed")
    end

    def method_not_allowed
      text_response(405, "Method Not Allowed")
    end

    def bad_request(body = "Bad Request")
      text_response(400, body)
    end

    def authorize!(context)
      return nil if context.resource_type == :dav_root
      return nil if context.public_token # public endpoint already authorized

      if context.username_from_path && context.user && context.username_from_path != context.user.username
        if context.resource_type == :addressbook || context.resource_type == :contact
          owner = User.find_by(username: context.username_from_path)
          return forbidden unless owner
          addressbook = owner.addressbooks.find_by(uri: context.addressbook_uri)
          return forbidden unless addressbook
          share = addressbook.shares.for_user(context.user).first
          return forbidden unless share
          context.share = share
          context.shared_addressbook = addressbook
        else
          return forbidden
        end
      elsif context.user && (context.resource_type == :addressbook || context.resource_type == :contact)
        book = context.user.addressbooks.find_by(uri: context.addressbook_uri)
        if book && !addressbook_authenticated?(context, book)
          return forbidden
        end
      end
      nil
    end

    def require_writable!(context)
      if context.public_token
        return forbidden
      end
      if context.share && !context.share.writable?
        return forbidden
      end
      nil
    end

    def require_owner!(context)
      return forbidden if context.public_token || context.share
      nil
    end

    def find_addressbook(context)
      if context.shared_addressbook
        context.shared_addressbook
      elsif context.public_token
        share = AddressbookShare.find_by(token: context.public_token)
        share&.addressbook
      else
        book = context.user.addressbooks.find_by(uri: context.addressbook_uri)
        return nil unless book
        return book if addressbook_authenticated?(context, book)
        nil
      end
    end

    def addressbook_authenticated?(context, book)
      Array(context.authenticated_addressbooks).any? { |ab| ab.id == book.id }
    end

    def find_contact(addressbook, context)
      addressbook.contacts.find_by(uri: context.contact_uri)
    end
  end
end
