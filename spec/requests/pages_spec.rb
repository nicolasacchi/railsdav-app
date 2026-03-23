require "rails_helper"

RSpec.describe "Public Pages", type: :request do
  describe "GET / (landing page)" do
    it "renders the landing page for unauthenticated users" do
      get root_path
      expect(response).to have_http_status(200)
      expect(response.body).to include("Your Contacts")
      expect(response.body).to include("Your Server")
    end

    it "redirects authenticated users to dashboard" do
      user = create(:user)
      post login_path, params: { email: user.email, password: "password123" }
      get root_path
      expect(response).to redirect_to(addressbooks_path)
    end
  end

  describe "GET /terms" do
    it "renders the terms page" do
      get terms_path
      expect(response).to have_http_status(200)
      expect(response.body).to include("Terms")
    end
  end

  describe "GET /privacy" do
    it "renders the privacy page" do
      get privacy_path
      expect(response).to have_http_status(200)
      expect(response.body).to include("Privacy")
    end
  end

  describe "GET /cookies" do
    it "renders the cookies page" do
      get cookies_path
      expect(response).to have_http_status(200)
      expect(response.body).to include("Cookie")
    end
  end
end
