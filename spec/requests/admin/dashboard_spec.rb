require "rails_helper"

RSpec.describe "Admin::Dashboard", type: :request do
  let(:admin) { create(:user, :admin) }
  let(:user) { create(:user) }

  describe "GET /admin" do
    it "redirects non-admin users" do
      post login_path, params: { email: user.email, password: "password123" }
      get admin_root_path
      expect(response).to redirect_to(root_path)
    end

    it "redirects unauthenticated users" do
      get admin_root_path
      expect(response).to redirect_to(login_path)
    end

    it "renders dashboard for admin" do
      post login_path, params: { email: admin.email, password: "password123" }
      get admin_root_path
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Admin Dashboard")
    end

    it "shows correct stats" do
      create_list(:user, 3)

      post login_path, params: { email: admin.email, password: "password123" }
      get admin_root_path
      expect(response.body).to include("Total Users")
      expect(response.body).to include("Total Contacts")
    end
  end
end
