module CardDav
  module Handlers
    class PutHandler
      include ResponseHelper

      def call(context)
        auth_error = authorize!(context)
        return auth_error if auth_error

        write_error = require_writable!(context)
        return write_error if write_error

        return bad_request("Request body required") unless context.body
        return text_response(413, "Request body too large") if context.body.bytesize > 1_048_576

        unless context.resource_type == :contact
          return text_response(409, "Conflict: cannot PUT to a collection")
        end

        vcard_data = context.body
        uid = extract_uid(vcard_data)
        return bad_request("vCard must contain a UID property") unless uid

        addressbook = find_addressbook(context)
        return not_found unless addressbook

        existing = find_contact(addressbook, context)

        if existing
          update_contact(context, addressbook, existing, vcard_data)
        else
          create_contact(context, addressbook, vcard_data)
        end
      end

      private

      def extract_uid(vcard_data)
        vcard_data.each_line do |line|
          match = line.strip.match(/\AUID(?:;[^:]*)?:(.+)/i)
          return match[1].strip if match
        end
        nil
      end

      def update_contact(context, addressbook, contact, vcard_data)
        if context.if_none_match == ["*"]
          return precondition_failed
        end

        if context.if_match && !context.if_match.include?(contact.etag)
          return precondition_failed
        end

        ActiveRecord::Base.transaction do
          contact.update!(vcard_data: vcard_data)
          addressbook.increment_sync!
          addressbook.sync_changes.create!(
            uri: contact.uri,
            sync_token: addressbook.sync_token,
            change_type: "modified"
          )
        end

        empty_response(204, { "ETag" => contact.etag })
      end

      def create_contact(context, addressbook, vcard_data)
        if context.if_match
          return precondition_failed
        end

        contact = nil
        ActiveRecord::Base.transaction do
          contact = addressbook.contacts.create!(
            uri: context.contact_uri,
            vcard_data: vcard_data
          )
          addressbook.increment_sync!
          addressbook.sync_changes.create!(
            uri: contact.uri,
            sync_token: addressbook.sync_token,
            change_type: "created"
          )
        end

        empty_response(201, { "ETag" => contact.etag })
      end
    end
  end
end
