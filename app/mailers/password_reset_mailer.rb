class PasswordResetMailer < ApplicationMailer
  def reset_email(user)
    @user = user
    @reset_url = reset_password_url(token: user.password_reset_token)
    mail(to: user.email, subject: "Reset your password")
  end
end
