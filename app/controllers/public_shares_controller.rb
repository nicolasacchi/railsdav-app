class PublicSharesController < ApplicationController
  skip_before_action :require_login

  def show
    @share = AddressbookShare.find_by!(token: params[:token])
    @addressbook = @share.addressbook
    @contacts = @addressbook.contacts.order(:uri)
    @displays = @contacts.map { |c| Vcard::Parser.parse(c.vcard_data) }
  end
end
