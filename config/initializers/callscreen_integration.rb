# Sanity-check the env vars that gate the internal JSON API endpoints used
# by callscreen.
#
# CALLSCREEN_API_TOKEN  — required for the endpoints to be enabled at all
#                          (gates /api/contact_lookup AND /api/spam_reports).
# CALLSCREEN_API_USERNAME — only consumed as a fallback when callscreen does
# not pass `?username=…` on the request. Multi-tenant callscreen passes the
# username per call, so missing env is no longer a configuration error.
Rails.application.config.after_initialize do
  next if Rails.env.test?

  token_set = ENV["CALLSCREEN_API_TOKEN"].to_s.present?
  unless token_set
    Rails.logger.warn(
      "[callscreen integration] CALLSCREEN_API_TOKEN is not set; /api/contact_lookup and /api/spam_reports will return 503 until configured."
    )
  end
end
