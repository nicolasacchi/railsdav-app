require "rails_helper"

RSpec.describe "Contact Groups", type: :request do
  let!(:user) { create(:user, username: "alice", password: "password123") }
  let(:addressbook) { user.addressbooks.first }

  def login_as(user)
    post login_path, params: { email: user.email, password: "password123" }
    follow_redirect!
  end

  before { login_as(user) }

  describe "POST /addressbooks/:uri/groups (create)" do
    it "creates a group" do
      expect {
        post addressbook_groups_path(addressbook.uri), params: { name: "Family" }
      }.to change(ContactGroup, :count).by(1)
      expect(addressbook.contact_groups.find_by(name: "Family")).to be_present
    end

    it "rejects blank name" do
      expect {
        post addressbook_groups_path(addressbook.uri), params: { name: "" }
      }.not_to change(ContactGroup, :count)
    end

    it "rejects duplicate name in same addressbook" do
      create(:contact_group, addressbook: addressbook, name: "Family")
      expect {
        post addressbook_groups_path(addressbook.uri), params: { name: "Family" }
      }.not_to change(ContactGroup, :count)
    end

    it "redirects back" do
      post addressbook_groups_path(addressbook.uri), params: { name: "Work" }
      expect(response).to redirect_to(addressbook_path(addressbook.uri))
    end
  end

  describe "PATCH /addressbooks/:uri/groups/:id (rename)" do
    let!(:group) { create(:contact_group, addressbook: addressbook, name: "Old Name") }

    it "renames the group" do
      patch addressbook_group_path(addressbook.uri, group), params: { name: "New Name" }
      expect(group.reload.name).to eq("New Name")
    end

    it "cascades rename to member contacts' CATEGORIES" do
      vcard = "BEGIN:VCARD\r\nVERSION:3.0\r\nUID:uid-1\r\nFN:Alice\r\nCATEGORIES:Old Name,Friends\r\nEND:VCARD\r\n"
      contact = create(:contact, addressbook: addressbook, uid: "uid-1", uri: "alice.vcf", vcard_data: vcard)

      patch addressbook_group_path(addressbook.uri, group), params: { name: "New Name" }

      contact.reload
      parsed = Vcard::Parser.parse(contact.vcard_data)
      expect(parsed.categories).to include("New Name")
      expect(parsed.categories).to include("Friends")
      expect(parsed.categories).not_to include("Old Name")
    end

    it "cascades rename to KIND:group vCard FN" do
      group_vcard = "BEGIN:VCARD\r\nVERSION:3.0\r\nUID:grp-uid\r\nKIND:group\r\nFN:Old Name\r\nN:Old Name;;;;\r\nEND:VCARD\r\n"
      gc = create(:contact, addressbook: addressbook, uid: "grp-uid", uri: "group.vcf", vcard_data: group_vcard)
      group.update!(group_contact: gc)

      patch addressbook_group_path(addressbook.uri, group), params: { name: "New Name" }

      gc.reload
      expect(gc.vcard_data).to include("FN:New Name")
    end

    it "increments sync token" do
      old_token = addressbook.sync_token
      patch addressbook_group_path(addressbook.uri, group), params: { name: "New Name" }
      expect(addressbook.reload.sync_token).to be > old_token
    end
  end

  describe "DELETE /addressbooks/:uri/groups/:id (destroy)" do
    let!(:group) { create(:contact_group, addressbook: addressbook, name: "ToDelete") }

    it "destroys the group" do
      expect {
        delete addressbook_group_path(addressbook.uri, group)
      }.to change(ContactGroup, :count).by(-1)
    end

    it "removes category from member contacts" do
      vcard = "BEGIN:VCARD\r\nVERSION:3.0\r\nUID:uid-1\r\nFN:Alice\r\nCATEGORIES:ToDelete,Keep\r\nEND:VCARD\r\n"
      contact = create(:contact, addressbook: addressbook, uid: "uid-1", uri: "alice.vcf", vcard_data: vcard)

      delete addressbook_group_path(addressbook.uri, group)

      contact.reload
      parsed = Vcard::Parser.parse(contact.vcard_data)
      expect(parsed.categories).to eq(["Keep"])
      expect(parsed.categories).not_to include("ToDelete")
    end

    it "destroys KIND:group vCard if linked" do
      group_vcard = "BEGIN:VCARD\r\nVERSION:3.0\r\nUID:grp-uid\r\nKIND:group\r\nFN:ToDelete\r\nN:ToDelete;;;;\r\nEND:VCARD\r\n"
      gc = create(:contact, addressbook: addressbook, uid: "grp-uid", uri: "group.vcf", vcard_data: group_vcard)
      group.update!(group_contact: gc)

      expect {
        delete addressbook_group_path(addressbook.uri, group)
      }.to change(Contact, :count).by(-1)
    end

    it "increments sync token" do
      old_token = addressbook.sync_token
      delete addressbook_group_path(addressbook.uri, group)
      expect(addressbook.reload.sync_token).to be > old_token
    end

    it "redirects back with notice" do
      delete addressbook_group_path(addressbook.uri, group)
      expect(response).to redirect_to(addressbook_path(addressbook.uri))
      follow_redirect!
      expect(response.body).to include("Contacts were not removed")
    end
  end

  describe "Contacts index group filtering" do
    let!(:group) { create(:contact_group, addressbook: addressbook, name: "Family") }
    let!(:contact_in_group) do
      vcard = "BEGIN:VCARD\r\nVERSION:3.0\r\nUID:in-grp\r\nFN:Alice\r\nCATEGORIES:Family\r\nEND:VCARD\r\n"
      create(:contact, addressbook: addressbook, uid: "in-grp", uri: "alice.vcf", vcard_data: vcard)
    end
    let!(:contact_not_in_group) do
      vcard = "BEGIN:VCARD\r\nVERSION:3.0\r\nUID:not-grp\r\nFN:Bob\r\nEND:VCARD\r\n"
      create(:contact, addressbook: addressbook, uid: "not-grp", uri: "bob.vcf", vcard_data: vcard)
    end

    it "shows all contacts without group filter" do
      get all_contacts_path
      expect(response.body).to include("Alice")
      expect(response.body).to include("Bob")
    end

    it "filters contacts by group" do
      get all_contacts_path, params: { group_id: group.id }
      expect(response.body).to include("Alice")
      expect(response.body).not_to include("Bob")
    end

    it "shows group filter pills" do
      get all_contacts_path
      expect(response.body).to include("Family")
      expect(response.body).to include("group-tag")
    end

    it "hides KIND:group vCards from contact list" do
      group_vcard = "BEGIN:VCARD\r\nVERSION:3.0\r\nUID:grp-vcard\r\nKIND:group\r\nFN:HiddenGroupVcard\r\nN:HiddenGroupVcard;;;;\r\nEND:VCARD\r\n"
      create(:contact, addressbook: addressbook, uid: "grp-vcard", uri: "grpcard.vcf", vcard_data: group_vcard)

      get all_contacts_path
      # The group vCard should not appear as a contact-item in the list
      # (it may appear as a group tag name in filter pills, but not as a contact)
      doc = Nokogiri::HTML(response.body)
      contact_names = doc.css(".contact-item .contact-name a").map(&:text).map(&:strip)
      expect(contact_names).not_to include("HiddenGroupVcard")
    end
  end

  describe "Contact create/update with group_ids" do
    let!(:group) { create(:contact_group, addressbook: addressbook, name: "Work") }

    it "injects CATEGORIES when creating with group_ids" do
      post addressbook_contacts_path(addressbook.uri), params: {
        first_name: "Test",
        last_name: "User",
        group_ids: [group.id]
      }
      contact = addressbook.contacts.last
      parsed = Vcard::Parser.parse(contact.vcard_data)
      expect(parsed.categories).to include("Work")
    end

    it "injects CATEGORIES when updating with group_ids" do
      contact = create(:contact, addressbook: addressbook)
      patch addressbook_contact_path(addressbook.uri, contact.uri), params: {
        first_name: "Updated",
        group_ids: [group.id]
      }
      contact.reload
      parsed = Vcard::Parser.parse(contact.vcard_data)
      expect(parsed.categories).to include("Work")
    end
  end
end
