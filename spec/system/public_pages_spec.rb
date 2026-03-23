require "rails_helper"

RSpec.describe "Public pages", type: :system do
  it "shows the homepage" do
    visit root_path
    expect(page).to have_content("Your Contacts")
    expect(page).to have_link("Get Started")
  end

  it "shows the privacy policy" do
    visit privacy_path
    expect(page).to have_content("Privacy")
  end

  it "shows the terms of service" do
    visit terms_path
    expect(page).to have_content("Terms")
  end

  it "shows the cookie policy" do
    visit cookies_path
    expect(page).to have_content("Cookie")
  end

  it "redirects unauthenticated users from /contacts to login" do
    visit all_contacts_path
    expect(page).to have_current_path(login_path)
    expect(page).to have_content("Log In")
  end

  it "redirects unauthenticated users from /addressbooks to login" do
    visit addressbooks_path
    expect(page).to have_current_path(login_path)
  end
end
