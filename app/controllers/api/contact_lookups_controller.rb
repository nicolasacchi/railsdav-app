module Api
  class ContactLookupsController < BaseController
    include ResolvesApiUser
    before_action :resolve_api_user!

    def show
      result = Contacts::PhoneLookup.find_by_e164(params[:phone], user: @api_user)
      # `active` decays a lone, long-dormant report so a recycled number doesn't
      # hard-block a now-legitimate caller forever.
      spam   = SpamNumber.active.find_by(phone: SpamNumber.normalize_e164(params[:phone]))

      base = spam_payload(spam)
      if result.nil?
        render json: { match: false }.merge(base)
      else
        contact = result.contact
        render json: {
          match: true,
          name: contact.cached_display_name.presence,
          policy: result.policy,
          addressbook: contact.addressbook&.displayname,
          contact_id: contact.id,
          # kind + groups let callscreen's screener treat a named, operator-grouped
          # caller (Family, Doctors…) as a soft legitimacy signal.
          kind: contact.kind,
          groups: contact.contact_groups.pluck(:name)
        }.merge(base)
      end
    end

    private

    def spam_payload(spam)
      return { spam_global: false, spam_metadata: nil } if spam.nil?
      {
        spam_global: true,
        spam_metadata: {
          first_reported_at: spam.first_reported_at.iso8601,
          # last_seen_at lets callscreen weight by recency; notes carries the
          # WHY (e.g. callscreen's AI spam reason) back down to every operator.
          last_seen_at: spam.last_seen_at&.iso8601,
          source: spam.source,
          report_count: spam.report_count,
          notes: spam.notes.presence
        }
      }
    end

  end
end
