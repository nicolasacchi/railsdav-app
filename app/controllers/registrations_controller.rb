class RegistrationsController < ApplicationController
  skip_before_action :require_login
  skip_before_action :require_email

  def new
    @invitation_token = params[:invitation]

    if @invitation_token.present?
      @pending_share = AddressbookShare.find_by(invitation_token: @invitation_token, status: "pending")
      unless @pending_share
        return redirect_to login_path, alert: "Invalid or expired invitation."
      end
      if @pending_share.invitation_expired?
        return redirect_to login_path, alert: "This invitation has expired."
      end
      @user = User.new(email: @pending_share.invited_email)
    else
      unless Railsdav.allow_registration?
        return redirect_to login_path, alert: "Registration is not available."
      end
      @user = User.new
    end
  end

  def create
    @invitation_token = params[:invitation].presence || params.dig(:user, :invitation_token).presence

    if @invitation_token.present?
      @pending_share = AddressbookShare.find_by(invitation_token: @invitation_token, status: "pending")
      unless @pending_share
        return redirect_to login_path, alert: "Invalid or expired invitation."
      end
      if @pending_share.invitation_expired?
        return redirect_to login_path, alert: "This invitation has expired."
      end
    else
      unless Railsdav.allow_registration?
        return redirect_to login_path, alert: "Registration is not available."
      end
    end

    @user = User.new(registration_params)
    @user.email = @pending_share.invited_email if @pending_share

    if @user.save
      session[:user_id] = @user.id
      redirect_to all_contacts_path, notice: "Account created successfully."
    else
      render :new, status: :unprocessable_entity
    end
  end

  private

  def registration_params
    params.require(:user).permit(:username, :email, :password, :password_confirmation)
  end
end
