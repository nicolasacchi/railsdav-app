require "rails_helper"

RSpec.describe ContactGroupMembership, type: :model do
  let(:addressbook) { create(:addressbook) }
  let(:contact) { create(:contact, addressbook: addressbook) }
  let(:group) { create(:contact_group, addressbook: addressbook) }

  describe "validations" do
    it "prevents duplicate contact+group" do
      create(:contact_group_membership, contact: contact, contact_group: group)
      dup = ContactGroupMembership.new(contact: contact, contact_group: group)
      expect(dup).not_to be_valid
    end

    it "allows same contact in different groups" do
      group2 = create(:contact_group, addressbook: addressbook)
      create(:contact_group_membership, contact: contact, contact_group: group)
      m = ContactGroupMembership.new(contact: contact, contact_group: group2)
      expect(m).to be_valid
    end
  end

  describe "associations" do
    it "belongs to contact and contact_group" do
      m = create(:contact_group_membership, contact: contact, contact_group: group)
      expect(m.contact).to eq(contact)
      expect(m.contact_group).to eq(group)
    end
  end
end
