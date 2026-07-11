root = Rails.root
mw = ->(f) { require root.join("app/middleware/card_dav/#{f}") }

mw.call("xml/builder")
mw.call("xml/parser")
mw.call("xml/multi_status")
mw.call("response_helper")
mw.call("request_context")
mw.call("auth")
mw.call("properties/dav_properties")
mw.call("properties/carddav_properties")
mw.call("properties/calserver_properties")
mw.call("handlers/options_handler")
mw.call("handlers/get_handler")
mw.call("handlers/put_handler")
mw.call("handlers/delete_handler")
mw.call("handlers/propfind_handler")
mw.call("handlers/report_handler")
mw.call("handlers/mkcol_handler")
mw.call("handlers/proppatch_handler")
mw.call("router")
mw.call("middleware")

Rails.application.config.middleware.insert_before(Rails::Rack::Logger, CardDav::Middleware)

# CardDav::Middleware answers /dav/* directly and never calls into the Rails app,
# so Rack::Attack (installed near the bottom of the stack by its railtie) would
# never see DAV traffic and the "dav auth per ip" throttle would be dead code.
# Move Rack::Attack to sit OUTSIDE CardDav::Middleware so DAV Basic-auth attempts
# are rate-limited too. Guarded so a Rails middleware-API change can't break boot.
if defined?(Rack::Attack)
  begin
    Rails.application.config.middleware.move_before(CardDav::Middleware, Rack::Attack)
  rescue StandardError => e
    Rails.logger.warn("[card_dav] could not move Rack::Attack before CardDav::Middleware: #{e.class}: #{e.message}")
  end
end
