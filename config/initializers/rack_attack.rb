Rack::Attack.throttle("login attempts per ip", limit: 20, period: 1.hour) do |req|
  req.ip if req.path == "/login" && req.post?
end

Rack::Attack.throttle("requests per ip", limit: 300, period: 1.minute) do |req|
  req.ip
end

Rack::Attack.throttled_responder = lambda do |_request|
  [429, { "Content-Type" => "text/plain" }, ["Rate limit exceeded. Try again later.\n"]]
end
