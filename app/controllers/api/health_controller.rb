module Api
  # Liveness probe for callscreen's OperatorHealthWatchdogJob. Inherits the
  # Bearer-token gate from BaseController so it isn't a public surface. Returns a
  # cheap signal that railsdav is reachable AND its DB is queryable, so a
  # railsdav outage produces a proactive operator alert instead of callscreen's
  # contact lookups silently degrading to MISS.
  class HealthController < BaseController
    def show
      render json: { ok: true, spam_count: SpamNumber.count }
    end
  end
end
