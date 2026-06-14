require "rails_helper"

RSpec.describe SpamNumber, type: :model do
  describe "validations" do
    it "is valid with E.164 phone and a known source" do
      sn = SpamNumber.new(phone: "+393331234567", source: "manual")
      expect(sn).to be_valid
    end

    it "rejects an invalid phone" do
      sn = SpamNumber.new(phone: "abc", source: "manual")
      expect(sn).not_to be_valid
      expect(sn.errors[:phone]).to be_present
    end

    it "rejects an unknown source" do
      sn = SpamNumber.new(phone: "+393331234567", source: "evil")
      expect(sn).not_to be_valid
      expect(sn.errors[:source]).to be_present
    end

    it "accepts feed:<id> sources" do
      sn = SpamNumber.new(phone: "+393331234567", source: "feed:tellows")
      expect(sn).to be_valid
    end

    it "rejects malformed feed:<id> sources" do
      sn = SpamNumber.new(phone: "+393331234567", source: "feed:has spaces")
      expect(sn).not_to be_valid
    end

    it "enforces uniqueness on phone" do
      create(:spam_number, phone: "+393331234567")
      dup = SpamNumber.new(phone: "+393331234567", source: "manual")
      expect(dup).not_to be_valid
      expect(dup.errors[:phone]).to include("has already been taken")
    end
  end

  describe "normalization" do
    it "stores phone as E.164 from a national-format input" do
      sn = SpamNumber.create!(phone: "333 123 4567", source: "manual")
      expect(sn.phone).to eq("+393331234567")
    end

    it "leaves a valid E.164 input untouched" do
      sn = SpamNumber.create!(phone: "+393331234567", source: "manual")
      expect(sn.phone).to eq("+393331234567")
    end
  end

  describe "default timestamps on create" do
    it "sets first_reported_at and last_seen_at to now if absent" do
      sn = SpamNumber.create!(phone: "+393331234567", source: "manual")
      expect(sn.first_reported_at).to be_within(2.seconds).of(Time.current)
      expect(sn.last_seen_at).to be_within(2.seconds).of(sn.first_reported_at)
    end
  end

  describe ".upsert_report!" do
    it "creates a new row on first report" do
      expect {
        SpamNumber.upsert_report!(phone: "+393331234567", source: "ntfy_report",
                                  submitted_by_username: "nicola")
      }.to change(SpamNumber, :count).by(1)

      sn = SpamNumber.find_by!(phone: "+393331234567")
      expect(sn.report_count).to eq(1)
      expect(sn.source).to eq("ntfy_report")
      expect(sn.submitted_by_username).to eq("nicola")
    end

    it "is idempotent: bumps report_count and last_seen_at on re-report" do
      first  = SpamNumber.upsert_report!(phone: "+393331234567", source: "ntfy_report",
                                         submitted_by_username: "nicola")
      original_first_reported_at = first.first_reported_at
      original_username          = first.submitted_by_username
      sleep 0.01

      second = SpamNumber.upsert_report!(phone: "+393331234567", source: "ntfy_report",
                                         submitted_by_username: "someone-else")
      expect(second.id).to eq(first.id)
      expect(second.report_count).to eq(2)
      expect(second.last_seen_at).to be > original_first_reported_at
      expect(second.first_reported_at).to eq(original_first_reported_at)
      expect(second.submitted_by_username).to eq(original_username)
    end

    it "normalizes phone before upsert (national → E.164)" do
      SpamNumber.upsert_report!(phone: "+393331234567", source: "ntfy_report")
      sn = SpamNumber.upsert_report!(phone: "333 123 4567",     source: "ntfy_report")
      expect(sn.report_count).to eq(2)
      expect(sn.phone).to eq("+393331234567")
    end

    it "raises ArgumentError on invalid phone input" do
      expect {
        SpamNumber.upsert_report!(phone: "garbage", source: "ntfy_report")
      }.to raise_error(ArgumentError)
    end

    it "fills notes only on the first call (preserves existing notes)" do
      SpamNumber.upsert_report!(phone: "+393331234567", source: "ntfy_report", notes: "first note")
      again = SpamNumber.upsert_report!(phone: "+393331234567", source: "ntfy_report", notes: "second note")
      expect(again.notes).to eq("first note")
    end
  end

  describe ".recent scope" do
    it "orders by last_seen_at desc" do
      old = create(:spam_number, last_seen_at: 2.days.ago)
      mid = create(:spam_number, last_seen_at: 1.day.ago)
      new = create(:spam_number, last_seen_at: 1.minute.ago)
      expect(SpamNumber.recent.pluck(:id)).to eq([ new.id, mid.id, old.id ])
    end
  end
end
