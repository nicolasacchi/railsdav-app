module Api
  class ContactLookupsController < BaseController
    before_action :resolve_api_user!

    def show
      result = Contacts::PhoneLookup.find_by_e164(params[:phone], user: @api_user)
      spam   = SpamNumber.find_by(phone: SpamNumber.normalize_e164(params[:phone]))

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
          contact_id: contact.id
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

    # Multi-tenant resolution: callscreen passes ?username=… to look up
    # contacts in that tenant's address book. If absent, fall back to the
    # legacy single-user mode pinned by ENV["CALLSCREEN_API_USERNAME"].
    #
    #  - missing param AND missing env  → 503 (service misconfigured)
    #  - param/env names a non-existent user → 404 when param was given,
    #    503 when only env was set (preserves legacy behavior).
    def resolve_api_user!
      requested = params[:username].to_s.strip

      if requested.present?
        @api_user = User.find_by(username: requested) || User.find_by(email: requested)
        head :not_found if @api_user.nil?
        return
      end

      identifier = ENV["CALLSCREEN_API_USERNAME"].to_s.strip
      if identifier.blank?
        head :service_unavailable
        return
      end

      @api_user = User.find_by(username: identifier) || User.find_by(email: identifier)
      head :service_unavailable if @api_user.nil?
    end
  end
end
