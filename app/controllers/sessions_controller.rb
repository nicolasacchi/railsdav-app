class SessionsController < ApplicationController
  skip_before_action :require_login, only: [:new, :create]
  skip_before_action :require_email, only: [:new, :create]

  def new
  end

  def create
    user = User.find_by(email: params[:email]&.strip&.downcase)
    if user&.authenticate(params[:password])
      return_to = session[:return_to]
      reset_session
      session[:user_id] = user.id
      redirect_to return_to || all_contacts_path, notice: "Logged in successfully."
    else
      flash.now[:alert] = "Invalid email or password."
      render :new, status: :unprocessable_entity
    end
  end

  def destroy
    reset_session
    redirect_to login_path, notice: "Logged out."
  end
end
