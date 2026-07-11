module Callscreen
  # Opt-in outbound push so callscreen can invalidate its local cache the moment
  # an operator changes a caller's policy here, instead of waiting for its next
  # poll of /api/contact_lookup. No-op unless CALLSCREEN_WEBHOOK_URL is set.
  #
  # Deliberately fired only from the operator-driven API write endpoints
  # (contact_allows / contact_policies), not from bulk import / DAV / web edits —
  # those are many-at-a-time and are covered by callscreen's polling, so pushing
  # each one would flood the endpoint for no benefit.
  module_function

  def webhook_url
    ENV["CALLSCREEN_WEBHOOK_URL"].to_s.presence
  end

  def enabled?
    webhook_url.present?
  end

  def notify_contact_change(user:, contact:, event:)
    return unless enabled?

    CallscreenWebhookJob.perform_later(
      "event" => event.to_s,
      "username" => user&.username,
      "contact_id" => contact&.id,
      "phones" => contact ? contact.contact_phone_numbers.pluck(:e164) : []
    )
  rescue StandardError => e
    # Never let a notification failure break the operator's write.
    Rails.logger.warn("[callscreen] could not enqueue webhook: #{e.class}: #{e.message}")
    nil
  end
end
