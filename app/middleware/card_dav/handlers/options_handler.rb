module CardDav
  module Handlers
    class OptionsHandler
      include ResponseHelper

      ALLOWED_METHODS = "OPTIONS, GET, HEAD, PUT, DELETE, PROPFIND, PROPPATCH, REPORT, MKCOL".freeze
      DAV_COMPLIANCE = "1, 2, 3, addressbook".freeze

      def call(context)
        empty_response(200, {
          "Allow" => ALLOWED_METHODS,
          "DAV" => DAV_COMPLIANCE
        })
      end
    end
  end
end
