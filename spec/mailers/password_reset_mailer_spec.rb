require "rails_helper"

RSpec.describe PasswordResetMailer, type: :mailer do
  let(:user) { create(:user, email: "reset@example.com") }

  describe "#reset_email" do
    it "sends a working reset link to the user" do
      mail = described_class.reset_email(user)
      expect(mail.to).to eq(["reset@example.com"])
      expect(mail.subject).to eq("Reset your password")

      token = user.password_reset_token
      # A freshly generated token for the same user resolves back to them.
      expect(User.find_by_password_reset_token(token)).to eq(user)
      expect(mail.body.encoded).to include("password/reset")
    end
  end
end
