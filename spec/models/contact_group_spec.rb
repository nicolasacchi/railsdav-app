require "rails_helper"

RSpec.describe ContactGroup, type: :model do
  let(:addressbook) { create(:addressbook) }

  describe "validations" do
    it "requires a name" do
      group = ContactGroup.new(addressbook: addressbook, name: "")
      expect(group).not_to be_valid
      expect(group.errors[:name]).to include("can't be blank")
    end

    it "requires unique name per addressbook" do
      create(:contact_group, addressbook: addressbook, name: "Family")
      dup = ContactGroup.new(addressbook: addressbook, name: "Family")
      expect(dup).not_to be_valid
    end

    it "allows same name in different addressbooks" do
      ab2 = create(:addressbook)
      create(:contact_group, addressbook: addressbook, name: "Family")
      group = ContactGroup.new(addressbook: ab2, name: "Family")
      expect(group).to be_valid
    end
  end

  describe "associations" do
    it "belongs to addressbook" do
      group = create(:contact_group, addressbook: addressbook)
      expect(group.addressbook).to eq(addressbook)
    end

    it "has many contacts through memberships" do
      group = create(:contact_group, addressbook: addressbook)
      contact = create(:contact, addressbook: addressbook)
      create(:contact_group_membership, contact: contact, contact_group: group)
      expect(group.contacts).to include(contact)
    end

    it "destroys memberships when destroyed" do
      group = create(:contact_group, addressbook: addressbook)
      contact = create(:contact, addressbook: addressbook)
      create(:contact_group_membership, contact: contact, contact_group: group)
      expect { group.destroy! }.to change(ContactGroupMembership, :count).by(-1)
    end

    it "optionally links to a group_contact (KIND:group vCard)" do
      group_vcard = "BEGIN:VCARD\r\nVERSION:3.0\r\nUID:group-uid\r\nKIND:group\r\nFN:Family\r\nN:Family;;;;\r\nEND:VCARD\r\n"
      gc = create(:contact, addressbook: addressbook, uid: "group-uid", vcard_data: group_vcard)
      # sync_groups_from_vcard already creates the group, so find it
      group = addressbook.contact_groups.find_by(name: "Family")
      expect(group).to be_present
      expect(group.group_contact).to eq(gc)
    end
  end

  describe "scopes" do
    it "orders by name" do
      create(:contact_group, addressbook: addressbook, name: "Zzz")
      create(:contact_group, addressbook: addressbook, name: "Aaa")
      expect(ContactGroup.ordered.pluck(:name)).to eq(["Aaa", "Zzz"])
    end
  end
end
