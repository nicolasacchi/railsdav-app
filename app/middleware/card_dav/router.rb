module CardDav
  class Router
    def initialize
      @handlers = {
        "OPTIONS" => Handlers::OptionsHandler.new,
        "PROPFIND" => Handlers::PropfindHandler.new,
        "REPORT" => Handlers::ReportHandler.new,
        "GET" => Handlers::GetHandler.new,
        "HEAD" => Handlers::GetHandler.new,
        "PUT" => Handlers::PutHandler.new,
        "DELETE" => Handlers::DeleteHandler.new,
        "MKCOL" => Handlers::MkcolHandler.new,
        "PROPPATCH" => Handlers::ProppatchHandler.new
      }.freeze
    end

    def dispatch(context)
      handler = @handlers[context.method]
      if handler
        handler.call(context)
      else
        [405, {
          "Content-Type" => "text/plain",
          "Allow" => "OPTIONS, GET, HEAD, PUT, DELETE, PROPFIND, PROPPATCH, REPORT, MKCOL"
        }, ["Method Not Allowed"]]
      end
    end
  end
end
