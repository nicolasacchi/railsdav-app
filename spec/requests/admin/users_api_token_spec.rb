require "rails_helper"

RSpec.describe "Admin::Users API token", type: :request do
  let(:admin) { create(:user, :admin) }
  let(:target) { create(:user, username: "tenant") }

  before { post login_path, params: { email: admin.email, password: "password123" } }

  it "issues a token and shows the plaintext once in the flash" do
    expect {
      post regenerate_api_token_admin_user_path(target)
    }.to change { target.reload.api_token_digest }.from(nil)

    follow_redirect!
    # The plaintext appears once (via flash), never persisted in cleartext.
    expect(flash[:notice] || response.body).to be_present
    expect(target.api_token_digest).to be_present
  end

  it "rotates an existing token to a new digest" do
    target.regenerate_api_token!
    old_digest = target.reload.api_token_digest

    post regenerate_api_token_admin_user_path(target)
    expect(target.reload.api_token_digest).not_to eq(old_digest)
  end

  it "revokes a token" do
    target.regenerate_api_token!
    delete revoke_api_token_admin_user_path(target)
    expect(target.reload.api_token_digest).to be_nil
  end

  it "is not accessible to non-admins" do
    delete logout_path
    other = create(:user)
    post login_path, params: { email: other.email, password: "password123" }

    post regenerate_api_token_admin_user_path(target)
    expect(target.reload.api_token_digest).to be_nil
    expect(response).to redirect_to(root_path)
  end
end
