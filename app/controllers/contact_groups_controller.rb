class ContactGroupsController < ApplicationController
  before_action :set_addressbook
  before_action :set_group, only: [:update, :destroy]

  def create
    @addressbook.contact_groups.create!(name: params[:name])
    redirect_back fallback_location: addressbook_path(@addressbook.uri), notice: "Group created."
  rescue ActiveRecord::RecordInvalid => e
    redirect_back fallback_location: addressbook_path(@addressbook.uri), alert: e.message
  end

  def update
    old_name = @group.name
    new_name = params[:name]
    return redirect_back(fallback_location: addressbook_path(@addressbook.uri)) if new_name.blank?

    ActiveRecord::Base.transaction do
      @group.update!(name: new_name)

      # Update CATEGORIES in all member contacts' vcard_data
      @group.contacts.individuals.find_each do |contact|
        parsed = Vcard::Parser.parse(contact.vcard_data)
        next unless parsed

        categories = parsed.categories || []
        idx = categories.index { |c| c.casecmp(old_name) == 0 }
        next unless idx

        categories[idx] = new_name
        new_vcard = Vcard::Parser.update_categories(contact.vcard_data, categories)
        contact.update!(vcard_data: new_vcard)
        @addressbook.sync_changes.create!(uri: contact.uri, sync_token: @addressbook.sync_token, change_type: "modified")
      end

      # Update KIND:group vCard FN if exists
      if @group.group_contact
        gc = @group.group_contact
        new_vcard = gc.vcard_data.sub(/^FN:.+$/i, "FN:#{new_name}")
        gc.update!(vcard_data: new_vcard)
        @addressbook.sync_changes.create!(uri: gc.uri, sync_token: @addressbook.sync_token, change_type: "modified")
      end

      @addressbook.increment_sync!
    end

    redirect_back fallback_location: addressbook_path(@addressbook.uri), notice: "Group renamed."
  rescue ActiveRecord::RecordInvalid => e
    redirect_back fallback_location: addressbook_path(@addressbook.uri), alert: e.message
  end

  def destroy
    ActiveRecord::Base.transaction do
      # Remove category from member contacts' vcard_data
      @group.contacts.individuals.find_each do |contact|
        parsed = Vcard::Parser.parse(contact.vcard_data)
        next unless parsed

        categories = (parsed.categories || []).reject { |c| c.casecmp(@group.name) == 0 }
        new_vcard = Vcard::Parser.update_categories(contact.vcard_data, categories)
        contact.update!(vcard_data: new_vcard)
        @addressbook.sync_changes.create!(uri: contact.uri, sync_token: @addressbook.sync_token, change_type: "modified")
      end

      # Destroy KIND:group vCard if exists
      if @group.group_contact
        gc_uri = @group.group_contact.uri
        @group.group_contact.destroy!
        @addressbook.sync_changes.create!(uri: gc_uri, sync_token: @addressbook.sync_token, change_type: "deleted")
      end

      @group.destroy!
      @addressbook.increment_sync!
    end

    redirect_back fallback_location: addressbook_path(@addressbook.uri), notice: "Group deleted. Contacts were not removed."
  end

  private

  def set_addressbook
    @addressbook = current_user.addressbooks.find_by!(uri: params[:addressbook_uri])
  end

  def set_group
    @group = @addressbook.contact_groups.find(params[:id])
  end
end
