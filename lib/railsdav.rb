module Railsdav
  class << self
    def site_name
      ENV.fetch("SITE_NAME", "Contacts")
    end

    def site_url
      ENV.fetch("SITE_URL", "http://localhost:3000")
    end

    def allow_registration?
      ENV.fetch("ALLOW_REGISTRATION", "false") != "false"
    end

    def mailer_from
      ENV.fetch("MAILER_FROM", "noreply@example.com")
    end
  end
end
