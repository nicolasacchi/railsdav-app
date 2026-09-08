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

      matching = user.addressbooks.where.not(dav_password_digest: nil).select { |ab| ab.authenticate_dav(password) }
      return false if matching.empty?

      context.user = user
      context.authenticated_addressbooks = matching
      true
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
