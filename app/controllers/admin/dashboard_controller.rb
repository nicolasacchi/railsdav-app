module Admin
  class DashboardController < BaseController
    def index
      @total_users = User.count
      @total_contacts = Contact.count
      @total_addressbooks = Addressbook.count
      @recent_signups = User.where("created_at >= ?", 7.days.ago).count
      @recent_users = User.recent.limit(10)
    end
  end
end
