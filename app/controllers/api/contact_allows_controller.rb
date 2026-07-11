module Api
  # Lets callscreen propagate an operator's "trust this caller" decision UP into
  # the shared address book: when the operator taps Whitelist in an ntfy push,
  # callscreen POSTs here so the central policy learns it too (durable — it
  # survives a callscreen DB reset, and a future second tenant inherits it).
  #
  # Idempotent: an existing contact's policy is set to "allow"; an unknown number
  # creates a minimal contact in the user's default book. Both record a CardDAV
  # sync change so the operator's address-book clients pick it up.
  #
  # This is a thin "policy = allow" alias over ContactPoliciesController, kept for
  # backward compatibility with existing callscreen deployments.
  class ContactAllowsController < BaseController
    include ResolvesApiUser
    include ResolvesContactByPhone
    before_action :resolve_api_user!

    def create
      e164 = SpamNumber.normalize_e164(params[:phone])
      return render(json: { ok: false, error: "invalid_phone" }, status: :unprocessable_entity) if e164.nil?

      contact = existing_contact_for(e164)
      if contact
        contact.update!(call_screening_policy: "allow")
        contact.addressbook.record_sync_change!(uri: contact.uri, change_type: "modified")
      else
        book = target_addressbook_for_api_user
        return render(json: { ok: false, error: "no_addressbook" }, status: :unprocessable_entity) if book.nil?
        vcard = Vcard::Parser.generate(full_name: params[:name].to_s.presence || e164, phones: [ e164 ])
        contact = book.contacts.create!(uri: "#{SecureRandom.uuid}.vcf", vcard_data: vcard, call_screening_policy: "allow")
        book.record_sync_change!(uri: contact.uri, change_type: "created")
      end

      Callscreen.notify_contact_change(
        user: @api_user, contact: contact,
        event: contact.previously_new_record? ? "created" : "updated"
      )
      render json: { ok: true, contact_id: contact.id, policy: "allow", created: contact.previously_new_record? }
    end
  end
end
