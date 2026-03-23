require "rails_helper"

RSpec.describe "Admin::Users", type: :request do
  let(:admin) { create(:user, :admin) }
  let(:regular_user) { create(:user) }

  before do
    post login_path, params: { email: admin.email, password: "password123" }
  end

  describe "GET /admin/users" do
    it "redirects non-admin users" do
      delete logout_path
      post login_path, params: { email: regular_user.email, password: "password123" }
      get admin_users_path
      expect(response).to redirect_to(root_path)
    end

    it "lists all users" do
      create_list(:user, 3)
      get admin_users_path
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Users")
    end

    it "filters users by search query" do
      create(:user, username: "findme")
      create(:user, username: "other")
      get admin_users_path, params: { q: "findme" }
      expect(response.body).to include("findme")
      expect(response.body).not_to include(">other<")
    end
  end

  describe "GET /admin/users/:id" do
    it "shows user details" do
      get admin_user_path(regular_user)
      expect(response).to have_http_status(:ok)
      expect(response.body).to include(regular_user.username)
    end
  end

  describe "GET /admin/users/:id/edit" do
    it "renders edit form" do
      get edit_admin_user_path(regular_user)
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Edit:")
    end
  end

  describe "PATCH /admin/users/:id" do
    it "updates user" do
      patch admin_user_path(regular_user), params: { user: { email: "new@example.com" } }
      expect(response).to redirect_to(admin_user_path(regular_user))
      expect(regular_user.reload.email).to eq("new@example.com")
    end

    it "renders errors on invalid update" do
      other = create(:user, username: "taken")
      patch admin_user_path(regular_user), params: { user: { username: "taken" } }
      expect(response).to have_http_status(:unprocessable_entity)
    end

    it "toggles admin flag" do
      expect(regular_user.admin?).to be false
      patch admin_user_path(regular_user), params: { user: { admin: true } }
      expect(response).to redirect_to(admin_user_path(regular_user))
      expect(regular_user.reload.admin?).to be true

      patch admin_user_path(regular_user), params: { user: { admin: false } }
      expect(response).to redirect_to(admin_user_path(regular_user))
      expect(regular_user.reload.admin?).to be false
    end
  end

  describe "DELETE /admin/users/:id" do
    it "deletes user" do
      user_to_delete = create(:user)
      expect {
        delete admin_user_path(user_to_delete)
      }.to change(User, :count).by(-1)
      expect(response).to redirect_to(admin_users_path)
    end
  end
end
