class ContactsController < ApplicationController
  before_action :force_html_format, except: [:export]
  before_action :set_addressbook, except: [:index]
  before_action :set_contact, only: [:show, :edit, :update, :destroy, :export]

  def index
    owned_addressbooks = current_user.addressbooks
    shared_shares = current_user.addressbook_shares.accepted.includes(addressbook: :user)
    shared_addressbooks = shared_shares.map(&:addressbook)

    @addressbooks_for_filter = owned_addressbooks.to_a + shared_addressbooks
    @writable_addressbooks = owned_addressbooks.to_a + shared_addressbooks.select { |ab|
      shared_shares.find { |s| s.addressbook_id == ab.id }&.writable?
    }

    @selected_addressbook_id = params[:addressbook_id]&.to_i
    addressbooks_to_show = if @selected_addressbook_id && @selected_addressbook_id > 0
      target = @addressbooks_for_filter.find { |ab| ab.id == @selected_addressbook_id }
      target ? [target] : @addressbooks_for_filter
    else
      @addressbooks_for_filter
    end

    addressbook_ids = addressbooks_to_show.map(&:id)
    scope = Contact.individuals.non_bootstrap.where(addressbook_id: addressbook_ids).display_order

    # Group filtering
    @groups = ContactGroup.where(addressbook_id: addressbook_ids).ordered
    @selected_group_id = params[:group_id]&.to_i
    if @selected_group_id && @selected_group_id > 0
      scope = scope.joins(:contact_group_memberships)
                   .where(contact_group_memberships: { contact_group_id: @selected_group_id })
    end

    @contact_count = scope.count
    @pagy, contacts = pagy(scope)

    ab_lookup = addressbooks_to_show.index_by(&:id)
    @parsed_contacts = contacts.map do |c|
      display = c.encrypted? ? nil : Vcard::Parser.parse(c.vcard_data)
      { contact: c, display: display, addressbook: ab_lookup[c.addressbook_id] }
    end

    @grouped_contacts = @parsed_contacts.group_by do |item|
      first = item[:display]&.full_name&.strip&.first&.upcase || "#"
      first.match?(/[A-Z]/) ? first : "#"
    end
  end

  def show
    @display = @contact.encrypted? ? nil : Vcard::Parser.parse(@contact.vcard_data)
  end

  def new
    @contact = @addressbook.contacts.new
    @groups = @addressbook.contact_groups.ordered
  end

  def create
    vcard_data = if params[:raw_vcard].present?
      params[:raw_vcard]
    else
      Vcard::Parser.generate(contact_form_params)
    end

    # Inject CATEGORIES from group_ids if provided (and not raw vCard)
    if params[:raw_vcard].blank? && params[:group_ids].present?
      group_names = @addressbook.contact_groups.where(id: params[:group_ids]).pluck(:name)
      vcard_data = Vcard::Parser.update_categories(vcard_data, group_names) if group_names.any?
    end

    @contact = @addressbook.contacts.new(
      uri: generate_uri,
      vcard_data: vcard_data
    )

    if @contact.save
      @addressbook.record_sync_change!(uri: @contact.uri, change_type: "created")
      redirect_to addressbook_contact_path(@addressbook.uri, @contact.uri), notice: "Contact created."
    else
      @groups = @addressbook.contact_groups.ordered
      render :new, status: :unprocessable_entity
    end
  end

  def edit
    if @contact.encrypted?
      return redirect_to addressbook_contact_path(@addressbook.uri, @contact.uri),
                         alert: "Encrypted contacts can only be edited from the encrypting client."
    end
    @display = Vcard::Parser.parse(@contact.vcard_data)
    @groups = @addressbook.contact_groups.ordered
  end

  def update
    vcard_data = if params[:raw_vcard].present?
      params[:raw_vcard]
    else
      Vcard::Parser.generate(contact_form_params.merge(uid: @contact.uid))
    end

    # Inject CATEGORIES from group_ids if provided (and not raw vCard)
    if params[:raw_vcard].blank? && params[:group_ids].present?
      group_names = @addressbook.contact_groups.where(id: params[:group_ids]).pluck(:name)
      vcard_data = Vcard::Parser.update_categories(vcard_data, group_names) if group_names.any?
    elsif params[:raw_vcard].blank? && params.key?(:group_ids)
      # group_ids present but empty — clear categories
      vcard_data = Vcard::Parser.update_categories(vcard_data, [])
    end

    if @contact.update(vcard_data: vcard_data)
      @addressbook.record_sync_change!(uri: @contact.uri, change_type: "modified")
      redirect_to addressbook_contact_path(@addressbook.uri, @contact.uri), notice: "Contact updated."
    else
      @display = Vcard::Parser.parse(@contact.vcard_data)
      @groups = @addressbook.contact_groups.ordered
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    uri = @contact.uri
    @contact.destroy!
    @addressbook.record_sync_change!(uri: uri, change_type: "deleted")
    redirect_to all_contacts_path, notice: "Contact deleted."
  end

  def export
    if @contact.encrypted?
      send_data @contact.vcard_data, filename: @contact.uri,
                type: "application/octet-stream", disposition: "attachment"
      return
    end

    case params[:export_format]&.downcase
    when "vcf"
      send_data @contact.vcard_data, filename: @contact.uri, type: "text/vcard"
    when "csv"
      send_data Contacts::Exporter.to_csv([ @contact ]), filename: "#{@contact.uri.sub('.vcf', '')}.csv", type: "text/csv"
    when "json"
      send_data Contacts::Exporter.to_json([ @contact ]), filename: "#{@contact.uri.sub('.vcf', '')}.json", type: "application/json"
    else
      redirect_to addressbook_contact_path(@addressbook.uri, @contact.uri), alert: "Unknown export format."
    end
  end

  private

  def set_addressbook
    @addressbook = current_user.addressbooks.find_by(uri: params[:addressbook_uri])
    @addressbook ||= current_user.shared_addressbooks.find_by(uri: params[:addressbook_uri])
    raise ActiveRecord::RecordNotFound, "Addressbook not found" unless @addressbook
  end

  def set_contact
    @contact = @addressbook.contacts.find_by!(uri: params[:uri])
  end

  def contact_form_params
    params.permit(
      :full_name, :first_name, :last_name, :middle_name, :name_prefix, :name_suffix,
      :nickname, :pronouns, :gender, :role,
      :organization, :title, :note, :birthday, :anniversary, :photo_url,
      emails: [], phones: [], urls: [],
      addresses: [:type, :street, :city, :state, :zip, :country],
      impp: [:type, :value],
      social_profiles: [:type, :value]
    )
  end

  def generate_uri
    "#{SecureRandom.uuid}.vcf"
  end

  def force_html_format
    request.format = :html
  end
end
