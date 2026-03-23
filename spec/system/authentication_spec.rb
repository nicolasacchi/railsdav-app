require "rails_helper"

RSpec.describe "Authentication", type: :system do
  let!(:user) { create(:user, username: "alice", email: "alice@example.com", password: "password123") }

  describe "Login" do
    it "logs in with valid credentials" do
      visit login_path
      fill_in "Email", with: "alice@example.com"
      fill_in "Password", with: "password123"
      click_button "Log In"

      expect(page).to have_current_path(all_contacts_path)
      expect(page).to have_content("alice")
      expect(page).to have_button("Logout")
    end

    it "shows error with invalid credentials" do
      visit login_path
      fill_in "Email", with: "alice@example.com"
      fill_in "Password", with: "wrong"
      click_button "Log In"

      expect(page).to have_current_path(login_path)
      expect(page).to have_content("Invalid")
    end

    it "logs out" do
      visit login_path
      fill_in "Email", with: "alice@example.com"
      fill_in "Password", with: "password123"
      click_button "Log In"

      click_button "Logout"
      expect(page).to have_current_path(login_path)
    end
  end

  describe "Forgot password" do
    it "shows the forgot password page" do
      visit login_path
      click_link "Forgot password?"
      expect(page).to have_content("Forgot")
    end
  end
end
