module CardDav
  class Auth
    def self.authenticate(env, context)
      auth = Rack::Auth::Basic::Request.new(env)
      return false unless auth.provided? && auth.basic?

      login, password = auth.credentials
      user = if login.include?("@")
        User.find_by(email: login.downcase)
      else
        User.find_by(username: login)
      end
      return false unless user

      # Only accept per-addressbook DAV passwords (timing-safe).
      # The main password is intentionally excluded — DAV clients
      # must use the scoped DAV password, not the web login credential.
      user.addressbooks.where.not(dav_password: nil).each do |ab|
        if ActiveSupport::SecurityUtils.secure_compare(ab.dav_password, password)
          context.user = user
          return true
        end
      end

      false
    end

    def self.challenge_response
      [401, {
        "WWW-Authenticate" => 'Basic realm="CardDAV"',
        "Content-Type" => "text/plain",
        "Content-Length" => "12"
      }, ["Unauthorized"]]
    end
  end
end
