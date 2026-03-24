module CardDav
  module Handlers
    class DeleteHandler
      include ResponseHelper

      def call(context)
        auth_error = authorize!(context)
        return auth_error if auth_error

        write_error = require_writable!(context)
        return write_error if write_error

        case context.resource_type
        when :contact
          delete_contact(context)
        when :addressbook
          delete_addressbook(context)
        else
          method_not_allowed
        end
      end

      private

      def delete_contact(context)
        addressbook = find_addressbook(context)
        return not_found unless addressbook

        contact = find_contact(addressbook, context)
        return not_found unless contact

        if context.if_match && context.if_match != ["*"] && !context.if_match.include?(contact.etag)
          return precondition_failed
        end

        was_encrypted = contact.encrypted?
        was_bootstrap = contact.bootstrap_vcard?

        ActiveRecord::Base.transaction do
          contact.destroy!
          addressbook.record_sync_change!(uri: context.contact_uri, change_type: "deleted")
        end

        addressbook.update_encryption_status! if was_encrypted || was_bootstrap

        empty_response(204)
      end

      def delete_addressbook(context)
        addressbook = find_addressbook(context)
        return not_found unless addressbook

        addressbook.destroy!
        empty_response(204)
      end
    end
  end
end
