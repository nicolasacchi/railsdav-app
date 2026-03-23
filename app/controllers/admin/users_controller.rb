module Admin
  class UsersController < BaseController
    PER_PAGE = 25

    before_action :set_user, only: [ :show, :edit, :update, :destroy ]

    def index
      @users = User.recent
      if params[:q].present?
        q = "%#{params[:q]}%"
        @users = @users.where("username LIKE ? OR email LIKE ?", q, q)
      end
      @total = @users.count
      max_page = [(@total.to_f / PER_PAGE).ceil, 1].max
      @page = [[params[:page].to_i, 1].max, max_page].min
      @users = @users.offset((@page - 1) * PER_PAGE).limit(PER_PAGE)
    end

    def show
      @addressbook_count = @user.addressbooks.count
      @contact_count = Contact.joins(:addressbook).where(addressbooks: { user_id: @user.id }).count
    end

    def new
      @user = User.new
    end

    def create
      @user = User.new(create_user_params)
      if @user.save
        redirect_to admin_user_path(@user), notice: "User created."
      else
        render :new, status: :unprocessable_entity
      end
    end

    def edit
    end

    def update
      if @user.update(user_params)
        redirect_to admin_user_path(@user), notice: "User updated."
      else
        render :edit, status: :unprocessable_entity
      end
    end

    def destroy
      Rails.logger.info("[ADMIN] #{current_user.username} deleted user #{@user.username} (id=#{@user.id})")
      @user.destroy
      redirect_to admin_users_path, notice: "User deleted."
    end

    private

    def set_user
      @user = User.find(params[:id])
    end

    def create_user_params
      params.require(:user).permit(:username, :email, :password, :password_confirmation, :admin)
    end

    def user_params
      permitted = params.require(:user).permit(:username, :email, :admin, :password, :password_confirmation)
      permitted.delete(:password) if permitted[:password].blank?
      permitted.delete(:password_confirmation) if permitted[:password].blank?
      permitted
    end
  end
end
