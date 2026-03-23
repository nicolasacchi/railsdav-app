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
