require "rails_helper"

RSpec.describe Railsdav do
  describe ".site_name" do
    it "returns default" do
      allow(ENV).to receive(:fetch).and_call_original
      allow(ENV).to receive(:fetch).with("SITE_NAME", "Contacts").and_return("Contacts")
      expect(Railsdav.site_name).to eq("Contacts")
    end

    it "returns ENV value" do
      allow(ENV).to receive(:fetch).and_call_original
      allow(ENV).to receive(:fetch).with("SITE_NAME", "Contacts").and_return("My Contacts")
      expect(Railsdav.site_name).to eq("My Contacts")
    end
  end

  describe ".site_url" do
    it "returns default" do
      allow(ENV).to receive(:fetch).and_call_original
      allow(ENV).to receive(:fetch).with("SITE_URL", "http://localhost:3000").and_return("http://localhost:3000")
      expect(Railsdav.site_url).to eq("http://localhost:3000")
    end
  end

  describe ".allow_registration?" do
    it "returns false by default" do
      allow(ENV).to receive(:fetch).and_call_original
      allow(ENV).to receive(:fetch).with("ALLOW_REGISTRATION", "false").and_return("false")
      expect(Railsdav.allow_registration?).to be false
    end

    it "returns true when set to true" do
      allow(ENV).to receive(:fetch).and_call_original
      allow(ENV).to receive(:fetch).with("ALLOW_REGISTRATION", "false").and_return("true")
      expect(Railsdav.allow_registration?).to be true
    end
  end

  describe ".mailer_from" do
    it "returns default" do
      allow(ENV).to receive(:fetch).and_call_original
      allow(ENV).to receive(:fetch).with("MAILER_FROM", "noreply@example.com").and_return("noreply@example.com")
      expect(Railsdav.mailer_from).to eq("noreply@example.com")
    end
  end
end
