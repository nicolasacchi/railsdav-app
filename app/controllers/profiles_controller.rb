class ProfilesController < ApplicationController
  skip_before_action :require_email

  def edit
    @user = current_user
  end

  def update
    @user = current_user
    if @user.update(profile_params)
      redirect_to all_contacts_path, notice: "Profile updated."
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    @user = current_user
    if @user.authenticate(params[:password])
      @user.destroy!
      session.delete(:user_id)
      redirect_to login_path, notice: "Your account has been deleted."
    else
      redirect_to edit_profile_path, alert: "Incorrect password. Account not deleted."
    end
  end

  private

  def profile_params
    params.require(:user).permit(:email)
  end
end
