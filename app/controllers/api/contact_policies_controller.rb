module Api
  # General "set this caller's screening policy" endpoint — the block/screen
  # counterpart to ContactAllowsController. Lets callscreen push any operator
  # decision (block a scammer, force-screen, or allow) up into the tenant's book.
  #
  # Idempotent: sets an existing contact's policy, or creates a minimal contact
  # in the user's default book when the number is unknown. Records a CardDAV sync
  # change so DAV clients pick it up, and (if configured) pushes a webhook.
  class ContactPoliciesController < BaseController
    include ResolvesApiUser
    include ResolvesContactByPhone
    before_action :resolve_api_user!

    def create
      policy = params[:policy].to_s
      unless Addressbook::CALL_SCREENING_POLICIES.include?(policy)
        return render(json: { ok: false, error: "invalid_policy" }, status: :unprocessable_entity)
      end

      e164 = SpamNumber.normalize_e164(params[:phone])
      return render(json: { ok: false, error: "invalid_phone" }, status: :unprocessable_entity) if e164.nil?

      contact = existing_contact_for(e164)
      if contact
        contact.update!(call_screening_policy: policy)
        contact.addressbook.record_sync_change!(uri: contact.uri, change_type: "modified")
      else
        book = target_addressbook_for_api_user
        return render(json: { ok: false, error: "no_addressbook" }, status: :unprocessable_entity) if book.nil?
        vcard = Vcard::Parser.generate(full_name: params[:name].to_s.presence || e164, phones: [ e164 ])
        contact = book.contacts.create!(uri: "#{SecureRandom.uuid}.vcf", vcard_data: vcard, call_screening_policy: policy)
        book.record_sync_change!(uri: contact.uri, change_type: "created")
      end

      Callscreen.notify_contact_change(
        user: @api_user, contact: contact,
        event: contact.previously_new_record? ? "created" : "updated"
      )
      render json: { ok: true, contact_id: contact.id, policy: policy, created: contact.previously_new_record? }
    end
  end
end
