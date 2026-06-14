module Api
  # Endpoint for callscreen to enroll a phone number into the global
  # spam DB after an operator taps "Report globally" in the ntfy
  # notification. Idempotent — re-reporting bumps `report_count`.
  class SpamReportsController < BaseController
    def create
      e164 = SpamNumber.normalize_e164(params[:phone])
      return render(json: { ok: false, error: "invalid_phone" }, status: :unprocessable_entity) if e164.nil?

      source = params[:source].to_s.presence || "ntfy_report"
      unless valid_source?(source)
        return render(json: { ok: false, error: "invalid_source" }, status: :unprocessable_entity)
      end

      SpamNumber.upsert_report!(
        phone: e164,
        source: source,
        submitted_by_username: params[:submitted_by_username].to_s.presence,
        notes: params[:notes].to_s.presence
      )
      render json: { ok: true }
    end

    private

    def valid_source?(source)
      SpamNumber::SOURCES_WHITELIST.include?(source) ||
        source.match?(SpamNumber::FEED_SOURCE_FORMAT)
    end
  end
end
