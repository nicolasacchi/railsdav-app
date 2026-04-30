# Sanity-check the env vars that gate the /api/contact_lookup endpoint used by
# callscreen. If only one of the pair is set the endpoint silently 503s, which
# is hard to diagnose; warn loudly at boot to surface the misconfiguration.
Rails.application.config.after_initialize do
  next if Rails.env.test?

  token_set = ENV["CALLSCREEN_API_TOKEN"].to_s.present?
  user_set  = ENV["CALLSCREEN_API_USERNAME"].to_s.present?

  if token_set ^ user_set
    missing = token_set ? "CALLSCREEN_API_USERNAME" : "CALLSCREEN_API_TOKEN"
    Rails.logger.warn(
      "[callscreen integration] #{missing} is not set; /api/contact_lookup will return 503 until both env vars are configured."
    )
  end
end
