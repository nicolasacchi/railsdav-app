module CardDav
  class Middleware
    def initialize(app)
      @app = app
      @router = Router.new
    end

    def call(env)
      path = env["PATH_INFO"]

      if path.start_with?("/.well-known/carddav")
        [301, { "Location" => "/dav/", "Content-Length" => "0" }, []]
      elsif path.start_with?("/dav/public/")
        handle_public_dav(env)
      elsif path == "/dav" || path.start_with?("/dav/")
        handle_dav(env)
      else
        @app.call(env)
      end
    end

    private

    def handle_public_dav(env)
      context = RequestContext.new(env)
      method = env["REQUEST_METHOD"].upcase

      unless %w[OPTIONS PROPFIND REPORT GET HEAD].include?(method)
        return [403, { "Content-Type" => "text/plain", "Content-Length" => "9" }, ["Forbidden"]]
      end

      # Parse /dav/public/{token}/ or /dav/public/{token}/{card}.vcf
      segments = env["PATH_INFO"].sub(%r{^/dav/public/?}, "").split("/").reject(&:empty?)
      return [404, { "Content-Type" => "text/plain", "Content-Length" => "9" }, ["Not Found"]] if segments.empty?

      token = segments[0]
      share = AddressbookShare.find_by(token: token)
      return [404, { "Content-Type" => "text/plain", "Content-Length" => "9" }, ["Not Found"]] unless share

      addressbook = share.addressbook
      owner = addressbook.user

      # Rewrite context to point at the real addressbook
      context.public_token = token

      # Override path_segments to match addressbook/contact structure
      if segments.length == 1
        # /dav/public/{token}/ → addressbook collection
        context.path_segments = [ owner.username, "contacts", addressbook.uri ]
        context.resource_type = :addressbook
      elsif segments.length == 2
        # /dav/public/{token}/{card}.vcf → contact
        context.path_segments = [ owner.username, "contacts", addressbook.uri, segments[1] ]
        context.resource_type = :contact
      else
        return [404, { "Content-Type" => "text/plain", "Content-Length" => "9" }, ["Not Found"]]
      end

      @router.dispatch(context)
    rescue ActiveRecord::RecordNotFound
      [404, { "Content-Type" => "text/plain", "Content-Length" => "9" }, ["Not Found"]]
    rescue => e
      Rails.logger.error("CardDAV public error: #{e.message}")
      [500, { "Content-Type" => "text/plain", "Content-Length" => "21" }, ["Internal Server Error"]]
    end

    def handle_dav(env)
      context = RequestContext.new(env)

      unless Auth.authenticate(env, context)
        return Auth.challenge_response
      end

      @router.dispatch(context)
    rescue ActiveRecord::RecordNotFound
      [404, { "Content-Type" => "text/plain", "Content-Length" => "9" }, ["Not Found"]]
    rescue => e
      Rails.logger.error("CardDAV error: #{e.message}")
      [500, { "Content-Type" => "text/plain", "Content-Length" => "21" }, ["Internal Server Error"]]
    end
  end
end
