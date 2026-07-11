# Sanity-check the env vars that gate the internal JSON API endpoints used
# by callscreen.
#
# CALLSCREEN_API_TOKEN  — required for the endpoints to be enabled at all
#                          (gates /api/contact_lookup AND /api/spam_reports).
# CALLSCREEN_API_USERNAME — only consumed as a fallback when callscreen does
# not pass `?username=…` on the request. Multi-tenant callscreen passes the
# username per call, so missing env is no longer a configuration error.
# CALLSCREEN_WEBHOOK_URL   — optional. When set, operator policy changes made via
# the API are pushed here (see Callscreen / CallscreenWebhookJob) so callscreen
# can invalidate its cache without waiting to poll.
# CALLSCREEN_WEBHOOK_TOKEN — optional bearer token sent with those webhook POSTs.
Rails.application.config.after_initialize do
  next if Rails.env.test?

  token_set = ENV["CALLSCREEN_API_TOKEN"].to_s.present?
  unless token_set
    Rails.logger.warn(
      "[callscreen integration] CALLSCREEN_API_TOKEN is not set; the shared-token API path returns 503. " \
      "Per-tenant API tokens (issued from the admin user page) still work independently."
    )
  end

  if ENV["CALLSCREEN_WEBHOOK_URL"].to_s.present?
    Rails.logger.info("[callscreen integration] contact-change webhook enabled → #{ENV['CALLSCREEN_WEBHOOK_URL']}")
  end
end
