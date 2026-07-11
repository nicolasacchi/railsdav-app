module Api
  # Read/export of the global spam DB so callscreen can sync it locally instead
  # of round-tripping /api/contact_lookup for the spam signal on every call.
  # Supports incremental pulls via ?since=<iso8601> and ?active_only=true.
  class SpamNumbersController < BaseController
    DEFAULT_PER_PAGE = 100
    MAX_PER_PAGE = 500

    def index
      scope = SpamNumber.all
      scope = scope.active if truthy?(params[:active_only])

      if params[:since].present? && (since = parse_time(params[:since]))
        scope = scope.where("last_seen_at >= ?", since)
      end

      scope = scope.recent
      total = scope.count

      records = scope.offset((page - 1) * per_page).limit(per_page)

      render json: {
        ok: true,
        page: page,
        per_page: per_page,
        total: total,
        numbers: records.map { |s| spam_json(s) }
      }
    end

    private

    def per_page
      value = (params[:per_page].presence || DEFAULT_PER_PAGE).to_i
      value = DEFAULT_PER_PAGE if value <= 0
      [ value, MAX_PER_PAGE ].min
    end

    def page
      [ params[:page].to_i, 1 ].max
    end

    def truthy?(value)
      ActiveModel::Type::Boolean.new.cast(value) == true
    end

    def parse_time(value)
      Time.zone.parse(value.to_s)
    rescue ArgumentError, TypeError
      nil
    end

    def spam_json(spam)
      {
        phone: spam.phone,
        source: spam.source,
        report_count: spam.report_count,
        first_reported_at: spam.first_reported_at.iso8601,
        last_seen_at: spam.last_seen_at&.iso8601,
        notes: spam.notes.presence
      }
    end
  end
end
