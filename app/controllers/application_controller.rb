class ApplicationController < ActionController::Base
  include Pagy::Method
  include RailsdavAuthentication
  allow_browser versions: :modern
  stale_when_importmap_changes
  layout "application"
end
