class PagesController < ApplicationController
  skip_before_action :require_login

  def home
    redirect_to addressbooks_path if current_user
  end

  def terms; end
  def privacy; end
  def cookies; end
end
