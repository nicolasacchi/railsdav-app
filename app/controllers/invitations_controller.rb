class InvitationsController < ApplicationController
  skip_before_action :require_login, only: [:accept]
  skip_before_action :require_email, only: [:accept]

  def accept
    share = AddressbookShare.find_by(invitation_token: params[:token], status: "pending")

    unless share
      redirect_to login_path, alert: "Invalid or expired invitation."
      return
    end

    if share.invitation_expired?
      redirect_to login_path, alert: "This invitation has expired."
      return
    end

    if share.user_id.present?
      accept_for_existing_user(share)
    else
      redirect_to register_path(invitation: share.invitation_token)
    end
  end

  private

  def accept_for_existing_user(share)
    if current_user
      if current_user.id == share.user_id
        share.accept!
        redirect_to all_contacts_path, notice: "You now have access to #{share.addressbook.displayname}."
      else
        redirect_to all_contacts_path, alert: "This invitation was sent to a different account."
      end
    else
      session[:return_to] = accept_invitation_path(token: params[:token])
      redirect_to login_path, notice: "Please log in to accept the invitation."
    end
  end
end
