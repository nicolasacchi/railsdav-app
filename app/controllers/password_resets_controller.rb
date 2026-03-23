class PasswordResetsController < ApplicationController
  skip_before_action :require_login
  skip_before_action :require_email

  def new
  end

  def create
    user = User.find_by(email: params[:email]&.strip&.downcase)
    if user
      PasswordResetMailer.reset_email(user).deliver_later
    end
    redirect_to login_path, notice: "If that email is registered, you'll receive a password reset link shortly."
  end

  def edit
    @user = User.find_by_password_reset_token(params[:token])
    if @user.nil?
      redirect_to login_path, alert: "Password reset link is invalid or has expired."
    end
  end

  def update
    @user = User.find_by_password_reset_token(params[:token])
    if @user.nil?
      return redirect_to login_path, alert: "Password reset link is invalid or has expired."
    end

    if @user.update(password: params[:password], password_confirmation: params[:password_confirmation])
      reset_session
      session[:user_id] = @user.id
      redirect_to all_contacts_path, notice: "Password has been reset. You are now logged in."
    else
      render :edit, status: :unprocessable_entity
    end
  end
end
