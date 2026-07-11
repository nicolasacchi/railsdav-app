module Api
  # Base for the internal JSON API endpoints (called from callscreen
  # over a private network). Bearer-token auth via CALLSCREEN_API_TOKEN.
  # Auth uses fixed-length SHA256 digest comparison so the inputs to
  # `secure_compare` are always the same length — the comparison itself
  # cannot leak token length regardless of what the operator picked.
  class BaseController < ActionController::API
    before_action :authenticate_api_token!

    # Set when a per-tenant API token authenticated the request. When present,
    # ResolvesApiUser pins the tenant to this user and ignores ?username=.
    attr_reader :api_authenticated_user

    private

    def authenticate_api_token!
      provided = bearer_token
      global = ENV["CALLSCREEN_API_TOKEN"].to_s

      # 1. Shared global token — fast path, no DB. Tenant chosen via ?username=.
      if global.present? && provided.present? &&
         ActiveSupport::SecurityUtils.fixed_length_secure_compare(
           Digest::SHA256.digest(provided), Digest::SHA256.digest(global))
        return
      end

      # 2. Per-tenant token — pins the tenant, works even when no global token is
      #    configured. Only reached when the global token didn't match.
      if provided.present? && (user = User.authenticate_api_token(provided))
        @api_authenticated_user = user
        return
      end

      # 3. Nothing matched. When the global token isn't configured at all, report
      #    the service as unavailable (not merely unauthorized) so a misconfig is
      #    distinguishable — preserving the original contract.
      if global.blank?
        head :service_unavailable
      else
        head :unauthorized
      end
    end

    def bearer_token
      request.headers["Authorization"].to_s.sub(/\ABearer /, "")
    end
  end
end
