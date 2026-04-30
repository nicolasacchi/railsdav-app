module Api
  class ContactLookupsController < ActionController::API
    before_action :authenticate_api_token!
    before_action :resolve_api_user!

    def show
      result = Contacts::PhoneLookup.find_by_e164(params[:phone], user: @api_user)

      if result.nil?
        render json: { match: false }
      else
        contact = result.contact
        render json: {
          match: true,
          name: contact.cached_display_name.presence,
          policy: result.policy,
          addressbook: contact.addressbook&.displayname,
          contact_id: contact.id
        }
      end
    end

    private

    def authenticate_api_token!
      expected = ENV["CALLSCREEN_API_TOKEN"].to_s
      if expected.blank?
        head :service_unavailable
        return
      end

      provided = request.headers["Authorization"].to_s.sub(/\ABearer /, "")
      # SHA256 digests give us fixed-length inputs so the comparison itself
      # cannot leak token length, regardless of what the operator picked.
      expected_digest = Digest::SHA256.digest(expected)
      provided_digest = Digest::SHA256.digest(provided)
      unless ActiveSupport::SecurityUtils.fixed_length_secure_compare(provided_digest, expected_digest)
        head :unauthorized
      end
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
