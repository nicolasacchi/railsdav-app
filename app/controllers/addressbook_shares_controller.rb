class AddressbookSharesController < ApplicationController
  before_action :set_addressbook

  def create
    email = params[:email]&.strip&.downcase

    unless email.present? && email.match?(URI::MailTo::EMAIL_REGEXP)
      return redirect_to addressbook_path(@addressbook.uri), alert: "Please enter a valid email address."
    end

    if current_user.email == email
      return redirect_to addressbook_path(@addressbook.uri), alert: "Cannot share with yourself."
    end

    permission = %w[read write].include?(params[:permission]) ? params[:permission] : "read"
    existing_user = User.find_by(email: email)

    if existing_user
      share_with_existing_user(existing_user, email, permission)
    else
      invite_new_user(email, permission)
    end
  end

  def destroy
    share = @addressbook.shares.find(params[:id])
    share.destroy
    redirect_to addressbook_path(@addressbook.uri), notice: "Share removed."
  end

  def create_public_link
    unless @addressbook.shares.public_links.exists?
      @addressbook.shares.create!(permission: "read")
    end
    redirect_to addressbook_path(@addressbook.uri), notice: "Public link created."
  end

  def destroy_public_link
    @addressbook.shares.public_links.destroy_all
    redirect_to addressbook_path(@addressbook.uri), notice: "Public link removed."
  end

  private

  def set_addressbook
    @addressbook = current_user.addressbooks.find_by!(uri: params[:addressbook_uri] || params[:uri])
  end

  def share_with_existing_user(user, email, permission)
    existing_share = @addressbook.shares.find_by(user: user, status: "accepted")
    if existing_share
      existing_share.update!(permission: permission)
      return redirect_to addressbook_path(@addressbook.uri), notice: "Updated permissions for #{email}."
    end

    pending = @addressbook.shares.find_by(invited_email: email, status: "pending")
    if pending
      pending.update!(permission: permission, invitation_sent_at: Time.current)
      pending.regenerate_invitation_token!
      ShareMailer.invitation_existing_user(pending).deliver_later
      return redirect_to addressbook_path(@addressbook.uri), notice: "Re-sent invitation to #{email}."
    end

    share = @addressbook.shares.create!(
      user: user,
      invited_email: email,
      permission: permission,
      status: "pending",
      invitation_sent_at: Time.current
    )
    ShareMailer.invitation_existing_user(share).deliver_later
    redirect_to addressbook_path(@addressbook.uri), notice: "Invitation sent to #{email}."
  end

  def invite_new_user(email, permission)
    pending = @addressbook.shares.find_by(invited_email: email, status: "pending")
    if pending
      pending.update!(permission: permission, invitation_sent_at: Time.current)
      pending.regenerate_invitation_token!
      ShareMailer.invitation_new_user(pending).deliver_later
      return redirect_to addressbook_path(@addressbook.uri), notice: "Re-sent invitation to #{email}."
    end

    share = @addressbook.shares.create!(
      invited_email: email,
      permission: permission,
      status: "pending",
      invitation_sent_at: Time.current
    )
    ShareMailer.invitation_new_user(share).deliver_later
    redirect_to addressbook_path(@addressbook.uri), notice: "Invitation sent to #{email}."
  end
end
