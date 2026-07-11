require "e2ee/detection"

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

        vcard_data = context.body
        is_encrypted = E2ee::Detection.encrypted?(vcard_data)

        # Content-Type validation only for plaintext vCards
        if !is_encrypted && context.content_type && !context.content_type.match?(%r{text/vcard|text/x-vcard}i)
          return text_response(415, "Unsupported Media Type: expected text/vcard")
        end

        unless context.resource_type == :contact
          return text_response(409, "Conflict: cannot PUT to a collection")
        end

        # UID resolution: header → URI-derived → regex extraction (plaintext only)
        uid = if is_encrypted
          context.e2ee_uid || context.contact_uri&.sub(/\.vcf\z/i, "")
        else
          extract_uid(vcard_data)
        end
        return bad_request("vCard must contain a UID property") unless uid

        addressbook = find_addressbook(context)
        return not_found unless addressbook

        existing = find_contact(addressbook, context)

        if existing
          update_contact(context, addressbook, existing, vcard_data, encrypted: is_encrypted)
        else
          create_contact(context, addressbook, vcard_data, uid: uid, encrypted: is_encrypted)
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

      def update_contact(context, addressbook, contact, vcard_data, encrypted: false)
        if context.if_none_match == ["*"]
          return precondition_failed
        end

        if context.if_match && !context.if_match.include?(contact.etag)
          return precondition_failed
        end

        ActiveRecord::Base.transaction do
          contact.encrypted = encrypted
          contact.vcard_data = vcard_data
          contact.save!
          addressbook.record_sync_change!(uri: contact.uri, change_type: "modified")
          addressbook.update_encryption_status! if encrypted || contact.bootstrap_vcard?
        end

        empty_response(204, { "ETag" => contact.etag })
      rescue ActiveRecord::RecordNotUnique
        # The new vCard body carries a UID already used by a different contact in
        # this book — a no-uid-conflict precondition failure (RFC 6352 §6.3.2),
        # not a server error.
        text_response(409, "Conflict: a contact with this UID already exists in this addressbook")
      end

      def create_contact(context, addressbook, vcard_data, uid:, encrypted: false)
        if context.if_match
          return precondition_failed
        end

        if addressbook.contacts.exists?(uid: uid)
          return text_response(409, "Conflict: a contact with this UID already exists in this addressbook")
        end

        is_bootstrap = !encrypted && E2ee::Detection.bootstrap_vcard?(vcard_data)

        contact = nil
        ActiveRecord::Base.transaction do
          contact = addressbook.contacts.new(
            uri: context.contact_uri,
            uid: uid,
            encrypted: encrypted
          )
          contact.vcard_data = vcard_data
          contact.save!
          addressbook.record_sync_change!(uri: contact.uri, change_type: "created")
          addressbook.update_encryption_status! if encrypted || is_bootstrap
        end

        empty_response(201, { "ETag" => contact.etag })
      rescue ActiveRecord::RecordNotUnique
        # Lost the check-then-insert race against a concurrent PUT of the same UID.
        text_response(409, "Conflict: a contact with this UID already exists in this addressbook")
      end
    end
  end
end
