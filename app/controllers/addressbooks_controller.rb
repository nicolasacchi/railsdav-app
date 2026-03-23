class AddressbooksController < ApplicationController
  before_action :set_addressbook, only: [:show, :edit, :update, :destroy, :export, :import, :regenerate_dav_password]

  def index
    @addressbooks = current_user.addressbooks
  end

  def show
    scope = @addressbook.contacts.display_order
    @pagy, contacts = pagy(scope)
    @parsed_contacts = contacts.map do |c|
      { contact: c, display: Vcard::Parser.parse(c.vcard_data) }
    end
  end

  def new
    @addressbook = current_user.addressbooks.new
  end

  def create
    @addressbook = current_user.addressbooks.new(addressbook_params)
    if @addressbook.save
      redirect_to addressbook_path(@addressbook.uri), notice: "Addressbook created."
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit
  end

  def update
    if @addressbook.update(addressbook_params)
      redirect_to addressbook_path(@addressbook.uri), notice: "Addressbook updated."
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    @addressbook.destroy
    redirect_to all_contacts_path, notice: "Addressbook deleted."
  end

  def export
    contacts = @addressbook.contacts.order(:uri)
    case params[:export_format]&.downcase
    when "vcf"
      send_data Contacts::Exporter.to_vcf(contacts), filename: "#{@addressbook.uri}.vcf", type: "text/vcard"
    when "csv"
      send_data Contacts::Exporter.to_csv(contacts), filename: "#{@addressbook.uri}.csv", type: "text/csv"
    when "json"
      send_data Contacts::Exporter.to_json(contacts), filename: "#{@addressbook.uri}.json", type: "application/json"
    else
      redirect_to addressbook_path(@addressbook.uri), alert: "Unknown export format."
    end
  end

  def regenerate_dav_password
    plaintext = @addressbook.regenerate_dav_password!
    flash[:dav_password] = plaintext
    redirect_to addressbook_path(@addressbook.uri), notice: "DAV password regenerated. Copy it now — it won't be shown again."
  end

  def import
    file = params[:file]
    unless file.is_a?(ActionDispatch::Http::UploadedFile)
      return redirect_to addressbook_path(@addressbook.uri), alert: "Please select a file to import."
    end

    if file.size > 50.megabytes
      return redirect_to addressbook_path(@addressbook.uri), alert: "File too large (max 50MB)."
    end

    result = Contacts::Importer.new(
      addressbook: @addressbook,
      file: file,
      filename: file.original_filename
    ).call

    notice = "Imported #{result.imported} new, updated #{result.updated} existing."
    notice += " #{result.failed} failed." if result.failed > 0
    redirect_to addressbook_path(@addressbook.uri), notice: notice
  rescue Contacts::Importer::UnsupportedFormat
    redirect_to addressbook_path(@addressbook.uri), alert: "Unsupported file format. Please use .vcf, .csv, or .json."
  rescue Contacts::Importer::ParseError => e
    redirect_to addressbook_path(@addressbook.uri), alert: "Could not parse file: #{e.message}"
  end

  private

  def set_addressbook
    @addressbook = current_user.addressbooks.find_by!(uri: params[:uri])
  end

  def addressbook_params
    params.require(:addressbook).permit(:uri, :displayname, :description)
  end
end
