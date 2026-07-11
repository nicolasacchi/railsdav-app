require "net/http"
require "json"

# Best-effort delivery of a contact-change event to callscreen. Bounded retries;
# callscreen's polling is the fallback if the endpoint stays down.
class CallscreenWebhookJob < ApplicationJob
  queue_as :default

  retry_on StandardError, wait: 30.seconds, attempts: 3

  def perform(payload)
    url = Callscreen.webhook_url
    return if url.blank?

    uri = URI.parse(url)
    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = uri.scheme == "https"
    http.open_timeout = 3
    http.read_timeout = 5

    request = Net::HTTP::Post.new(uri.request_uri, "Content-Type" => "application/json")
    token = ENV["CALLSCREEN_WEBHOOK_TOKEN"].to_s
    request["Authorization"] = "Bearer #{token}" if token.present?
    request.body = payload.to_json

    response = http.request(request)
    unless response.is_a?(Net::HTTPSuccess)
      raise "callscreen webhook returned HTTP #{response.code}"
    end
  end
end
