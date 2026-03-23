module RailsdavAuthentication
  extend ActiveSupport::Concern

  included do
    helper_method :current_user
    before_action :require_login
    before_action :require_email
  end

  private

  def current_user
    @current_user ||= User.find_by(id: session[:user_id])
  end

  def require_login
    unless current_user
      redirect_to login_path, alert: "Please log in."
    end
  end

  def require_email
    if current_user && current_user.email.blank?
      redirect_to edit_profile_path, alert: "Please set your email address to continue."
    end
  end
end
