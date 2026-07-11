Rack::Attack.throttle("login attempts per ip", limit: 20, period: 1.hour) do |req|
  req.ip if req.path == "/login" && req.post?
end

Rack::Attack.throttle("password resets per ip", limit: 5, period: 1.hour) do |req|
  req.ip if req.path == "/password/forgot" && req.post?
end

Rack::Attack.throttle("dav auth per ip", limit: 20, period: 15.minutes) do |req|
  req.ip if req.path.start_with?("/dav/") && req.env["HTTP_AUTHORIZATION"].present?
end

Rack::Attack.throttle("contact lookup api per ip", limit: 60, period: 1.minute) do |req|
  req.ip if req.path.start_with?("/api/contact_lookup")
end

Rack::Attack.throttle("spam reports api per ip", limit: 60, period: 1.minute) do |req|
  req.ip if req.path.start_with?("/api/spam_reports") && req.post?
end

Rack::Attack.throttle("requests per ip", limit: 300, period: 1.minute) do |req|
  req.ip
end

Rack::Attack.throttled_responder = lambda do |request|
  body = "Rate limit exceeded. Try again later.\n"
  retry_after = request.env.dig("rack.attack.match_data", :period) || 60
  [429, {
    "Content-Type" => "text/plain",
    "Content-Length" => body.bytesize.to_s,
    "Retry-After" => retry_after.to_s
  }, [body]]
end
