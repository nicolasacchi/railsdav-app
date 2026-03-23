require "rails_helper"

RSpec.describe SyncChange, type: :model do
  let(:user) { create(:user) }
  let(:addressbook) { user.addressbooks.first }

  describe "validations" do
    it "requires uri" do
      sc = SyncChange.new(addressbook: addressbook, sync_token: 1, change_type: "created")
      expect(sc).not_to be_valid
    end

    it "requires sync_token" do
      sc = SyncChange.new(addressbook: addressbook, uri: "test.vcf", change_type: "created")
      expect(sc).not_to be_valid
    end

    it "requires change_type to be created, modified, or deleted" do
      sc = SyncChange.new(addressbook: addressbook, uri: "test.vcf", sync_token: 1, change_type: "invalid")
      expect(sc).not_to be_valid
    end

    it "accepts valid change_types" do
      %w[created modified deleted].each do |ct|
        sc = SyncChange.new(addressbook: addressbook, uri: "test.vcf", sync_token: 1, change_type: ct)
        expect(sc).to be_valid
      end
    end
  end

  describe ".since_token" do
    it "returns changes with sync_token greater than given value" do
      SyncChange.create!(addressbook: addressbook, uri: "a.vcf", sync_token: 1, change_type: "created")
      SyncChange.create!(addressbook: addressbook, uri: "b.vcf", sync_token: 2, change_type: "created")
      SyncChange.create!(addressbook: addressbook, uri: "c.vcf", sync_token: 3, change_type: "modified")

      result = SyncChange.since_token(1)
      expect(result.map(&:uri)).to contain_exactly("b.vcf", "c.vcf")
    end
  end
end
