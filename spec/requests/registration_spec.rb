require "rails_helper"

RSpec.describe "Registration", type: :request do
  describe "GET /register" do
    it "renders the registration form" do
      get register_path
      expect(response).to have_http_status(200)
      expect(response.body).to include("Create Account")
    end
  end

  describe "POST /register" do
    it "creates a new user and logs in" do
      expect {
        post register_path, params: { user: {
          username: "newuser",
          email: "new@example.com",
          password: "password123",
          password_confirmation: "password123"
        } }
      }.to change(User, :count).by(1)

      expect(response).to redirect_to(all_contacts_path)
      follow_redirect!
      expect(response.body).to include("newuser")
    end

    it "creates a default addressbook for the new user" do
      post register_path, params: { user: {
        username: "newuser",
        email: "new@example.com",
        password: "password123",
        password_confirmation: "password123"
      } }
      user = User.find_by(username: "newuser")
      expect(user.addressbooks.count).to eq(1)
    end

    it "auto-generates username from email when blank" do
      post register_path, params: { user: {
        email: "jane.doe@example.com",
        password: "password123",
        password_confirmation: "password123"
      } }
      expect(response).to redirect_to(all_contacts_path)
      user = User.find_by(email: "jane.doe@example.com")
      expect(user.username).to eq("jane.doe")
    end

    it "requires email" do
      post register_path, params: { user: {
        username: "noemail",
        password: "password123",
        password_confirmation: "password123"
      } }
      expect(response).to have_http_status(:unprocessable_entity)
    end

    it "shows errors for duplicate username" do
      create(:user, username: "existing")
      post register_path, params: { user: {
        username: "existing",
        email: "unique@example.com",
        password: "password123",
        password_confirmation: "password123"
      } }
      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.body).to include("has already been taken")
    end

    it "shows errors for password mismatch" do
      post register_path, params: { user: {
        email: "test@example.com",
        password: "password123",
        password_confirmation: "different"
      } }
      expect(response).to have_http_status(:unprocessable_entity)
    end
  end

  describe "when registration is disabled" do
    before { allow(Railsdav).to receive(:allow_registration?).and_return(false) }

    it "redirects GET /register to login" do
      get register_path
      expect(response).to redirect_to(login_path)
    end

    it "rejects POST /register" do
      post register_path, params: { user: {
        email: "blocked@example.com",
        password: "password123",
        password_confirmation: "password123"
      } }
      expect(response).to redirect_to(login_path)
    end
  end

  describe "invitation-based registration" do
    let(:owner) { create(:user) }
    let(:addressbook) { owner.addressbooks.first }

    it "allows registration with invitation even when registration is disabled" do
      allow(Railsdav).to receive(:allow_registration?).and_return(false)

      share = create(:addressbook_share, :pending_new_user,
        addressbook: addressbook,
        invited_email: "invited@example.com"
      )

      get register_path(invitation: share.invitation_token)
      expect(response).to have_http_status(200)

      post register_path(invitation: share.invitation_token), params: { user: {
        email: "invited@example.com",
        password: "password123",
        password_confirmation: "password123"
      } }
      expect(response).to redirect_to(all_contacts_path)

      user = User.find_by(email: "invited@example.com")
      expect(user).to be_present
      share.reload
      expect(share.status).to eq("accepted")
      expect(share.user_id).to eq(user.id)
    end

    it "rejects invalid invitation token" do
      allow(Railsdav).to receive(:allow_registration?).and_return(false)
      get register_path(invitation: "bogus-token")
      expect(response).to redirect_to(login_path)
    end
  end
end
