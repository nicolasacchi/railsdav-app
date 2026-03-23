class ShareMailer < ApplicationMailer
  def invitation_existing_user(share)
    @share = share
    @addressbook = share.addressbook
    @owner = @addressbook.user
    @accept_url = accept_invitation_url(token: share.invitation_token)
    mail(to: share.invited_email, subject: "#{@owner.username} shared an address book with you")
  end

  def invitation_new_user(share)
    @share = share
    @addressbook = share.addressbook
    @owner = @addressbook.user
    @register_url = register_url(invitation: share.invitation_token)
    mail(to: share.invited_email, subject: "#{@owner.username} invited you to #{Railsdav.site_name}")
  end
end
