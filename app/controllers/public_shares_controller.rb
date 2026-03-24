class PublicSharesController < ApplicationController
  skip_before_action :require_login

  def show
    @share = AddressbookShare.find_by!(token: params[:token])
    @addressbook = @share.addressbook
    @contacts = @addressbook.contacts.non_bootstrap.order(:uri)
    @displays = @contacts.map { |c| c.encrypted? ? nil : Vcard::Parser.parse(c.vcard_data) }
  end
end
