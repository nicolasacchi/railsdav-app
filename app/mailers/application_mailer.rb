class ApplicationMailer < ActionMailer::Base
  default from: -> { Railsdav.mailer_from }
  layout "mailer"
end
