require "rails_helper"

RSpec.describe "Admin::SpamNumbers", type: :request do
  let(:admin) { create(:user, :admin) }
  let(:regular_user) { create(:user) }

  before do
    post login_path, params: { email: admin.email, password: "password123" }
  end

  describe "GET /admin/spam_numbers" do
    it "redirects non-admin users" do
      delete logout_path
      post login_path, params: { email: regular_user.email, password: "password123" }
      get admin_spam_numbers_path
      expect(response).to redirect_to(root_path)
    end

    it "lists existing spam numbers" do
      create(:spam_number, phone: "+393331111111")
      create(:spam_number, phone: "+393332222222")
      get admin_spam_numbers_path
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("+393331111111")
      expect(response.body).to include("+393332222222")
    end

    it "filters by phone" do
      create(:spam_number, phone: "+393331111111")
      create(:spam_number, phone: "+393332222222")
      get admin_spam_numbers_path, params: { q: "1111111" }
      expect(response.body).to include("+393331111111")
      expect(response.body).not_to include("+393332222222")
    end

    it "shows an empty-state message when no rows exist" do
      get admin_spam_numbers_path
      expect(response.body).to include("No spam numbers yet.")
    end
  end

  describe "POST /admin/spam_numbers (single)" do
    it "creates a new spam_number with source: manual" do
      expect {
        post admin_spam_numbers_path, params: { spam_number: { phone: "+393331234567", notes: "Reported by user" } }
      }.to change(SpamNumber, :count).by(1)

      sn = SpamNumber.find_by!(phone: "+393331234567")
      expect(sn.source).to eq("manual")
      expect(sn.notes).to eq("Reported by user")
      expect(response).to redirect_to(admin_spam_number_path(sn))
    end

    it "rejects an invalid phone with 422" do
      post admin_spam_numbers_path, params: { spam_number: { phone: "garbage" } }
      expect(response).to have_http_status(:unprocessable_entity)
    end

    it "logs an [ADMIN] line on create" do
      allow(Rails.logger).to receive(:info)
      post admin_spam_numbers_path, params: { spam_number: { phone: "+393331234567" } }
      expect(Rails.logger).to have_received(:info).with(/\[ADMIN\] #{admin.username} added spam_number phone=\+393331234567/)
    end
  end

  describe "POST /admin/spam_numbers (bulk paste)" do
    it "imports valid numbers, skips invalid, updates existing" do
      create(:spam_number, phone: "+393331111111", report_count: 1)

      raw = "+393331111111\n+393332222222 +393333333333,garbage,not-a-phone"
      expect {
        post admin_spam_numbers_path, params: { bulk_phones: raw }
      }.to change(SpamNumber, :count).by(2)  # added 2, updated 1, skipped 2

      expect(response).to redirect_to(admin_spam_numbers_path)
      follow_redirect!
      expect(response.body).to include("added 2")
      expect(response.body).to include("updated 1")
      expect(response.body).to include("skipped 2 invalid")

      # Existing row's report_count bumped from 1 to 2
      expect(SpamNumber.find_by(phone: "+393331111111").report_count).to eq(2)
    end

    it "normalizes national-format numbers in bulk paste (one per line)" do
      post admin_spam_numbers_path, params: { bulk_phones: "3331234567\n3339999999" }
      expect(SpamNumber.find_by(phone: "+393331234567")).to be_present
      expect(SpamNumber.find_by(phone: "+393339999999")).to be_present
    end
  end

  describe "GET /admin/spam_numbers/:id" do
    it "shows full record details" do
      sn = create(:spam_number, phone: "+393331234567", source: "feed:tellows", report_count: 7)
      get admin_spam_number_path(sn)
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("+393331234567")
      expect(response.body).to include("feed:tellows")
      expect(response.body).to include("7")
    end
  end

  describe "PATCH /admin/spam_numbers/:id" do
    it "allows updating notes only" do
      sn = create(:spam_number, phone: "+393331234567", notes: "old note")
      patch admin_spam_number_path(sn), params: { spam_number: { notes: "new note" } }
      expect(response).to redirect_to(admin_spam_number_path(sn))
      expect(sn.reload.notes).to eq("new note")
    end

    it "ignores attempts to change phone (immutable)" do
      sn = create(:spam_number, phone: "+393331234567")
      patch admin_spam_number_path(sn), params: { spam_number: { phone: "+393339999999", notes: "x" } }
      expect(sn.reload.phone).to eq("+393331234567")
    end

    it "ignores attempts to change source (immutable)" do
      sn = create(:spam_number, phone: "+393331234567", source: "manual")
      patch admin_spam_number_path(sn), params: { spam_number: { source: "feed:evil", notes: "x" } }
      expect(sn.reload.source).to eq("manual")
    end
  end

  describe "DELETE /admin/spam_numbers/:id" do
    it "deletes the record and logs [ADMIN]" do
      sn = create(:spam_number, phone: "+393331234567")
      allow(Rails.logger).to receive(:info)
      expect {
        delete admin_spam_number_path(sn)
      }.to change(SpamNumber, :count).by(-1)
      expect(response).to redirect_to(admin_spam_numbers_path)
      expect(Rails.logger).to have_received(:info).with(/\[ADMIN\] #{admin.username} deleted spam_number phone=\+393331234567/)
    end
  end
end
