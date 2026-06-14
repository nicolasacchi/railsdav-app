module Api
  # Base for the internal JSON API endpoints (called from callscreen
  # over a private network). Bearer-token auth via CALLSCREEN_API_TOKEN.
  # Auth uses fixed-length SHA256 digest comparison so the inputs to
  # `secure_compare` are always the same length — the comparison itself
  # cannot leak token length regardless of what the operator picked.
  class BaseController < ActionController::API
    before_action :authenticate_api_token!

    private

    def authenticate_api_token!
      expected = ENV["CALLSCREEN_API_TOKEN"].to_s
      if expected.blank?
        head :service_unavailable
        return
      end

      provided = request.headers["Authorization"].to_s.sub(/\ABearer /, "")
      expected_digest = Digest::SHA256.digest(expected)
      provided_digest = Digest::SHA256.digest(provided)
      unless ActiveSupport::SecurityUtils.fixed_length_secure_compare(provided_digest, expected_digest)
        head :unauthorized
      end
    end
  end
end
