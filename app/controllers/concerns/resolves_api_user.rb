# Shared multi-tenant resolution for the internal callscreen API
# (Api::ContactLookupsController, Api::ContactAllowsController): callscreen passes
# ?username=… to address a specific tenant's book; absent that, fall back to the
# legacy single-user pin in ENV["CALLSCREEN_API_USERNAME"].
#
#  - missing param AND missing env   → 503 (service misconfigured)
#  - param names a non-existent user → 404
#  - env names a non-existent user   → 503 (preserves legacy behavior)
module ResolvesApiUser
  extend ActiveSupport::Concern

  private

  def resolve_api_user!
    # A per-tenant API token pins the tenant; ?username= is ignored so a token
    # scoped to one user can never read or write another tenant's book.
    if api_authenticated_user
      @api_user = api_authenticated_user
      return
    end

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
