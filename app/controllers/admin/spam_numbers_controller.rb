module Admin
  class SpamNumbersController < BaseController
    PER_PAGE = 25

    before_action :set_spam_number, only: [ :show, :edit, :update, :destroy ]

    def index
      @spam_numbers = SpamNumber.recent
      if params[:q].present?
        q = "%#{params[:q]}%"
        @spam_numbers = @spam_numbers.where("phone LIKE ?", q)
      end
      @total = @spam_numbers.count
      max_page = [ (@total.to_f / PER_PAGE).ceil, 1 ].max
      @page = [ [ params[:page].to_i, 1 ].max, max_page ].min
      @spam_numbers = @spam_numbers.offset((@page - 1) * PER_PAGE).limit(PER_PAGE)
    end

    def show
    end

    def new
      @spam_number = SpamNumber.new
    end

    def create
      if params[:bulk_phones].present?
        result = bulk_upsert(params[:bulk_phones])
        redirect_to admin_spam_numbers_path,
                    notice: "Bulk import: added #{result[:added]}, updated #{result[:updated]}, skipped #{result[:invalid]} invalid."
      else
        @spam_number = SpamNumber.new(create_params.merge(source: "manual"))
        if @spam_number.save
          Rails.logger.info("[ADMIN] #{current_user.username} added spam_number phone=#{@spam_number.phone} id=#{@spam_number.id}")
          redirect_to admin_spam_number_path(@spam_number), notice: "Spam number added."
        else
          render :new, status: :unprocessable_entity
        end
      end
    end

    def edit
    end

    def update
      # Phone and source are immutable post-create — only notes can be edited.
      if @spam_number.update(update_params)
        redirect_to admin_spam_number_path(@spam_number), notice: "Notes updated."
      else
        render :edit, status: :unprocessable_entity
      end
    end

    def destroy
      Rails.logger.info("[ADMIN] #{current_user.username} deleted spam_number phone=#{@spam_number.phone} id=#{@spam_number.id}")
      @spam_number.destroy
      redirect_to admin_spam_numbers_path, notice: "Spam number removed."
    end

    private

    def set_spam_number
      @spam_number = SpamNumber.find(params[:id])
    end

    def create_params
      params.require(:spam_number).permit(:phone, :notes)
    end

    def update_params
      params.require(:spam_number).permit(:notes)
    end

    # Bulk paste: split on whitespace and commas, normalize each, upsert
    # as `source: "manual"`. Returns counters for the redirect flash.
    def bulk_upsert(raw)
      tokens = raw.to_s.split(/[\s,]+/).reject(&:blank?)
      added = updated = invalid = 0
      tokens.each do |token|
        e164 = SpamNumber.normalize_e164(token)
        if e164.nil?
          invalid += 1
          next
        end
        before = SpamNumber.exists?(phone: e164)
        SpamNumber.upsert_report!(
          phone: e164, source: "manual",
          submitted_by_username: current_user.username
        )
        before ? updated += 1 : added += 1
      end
      Rails.logger.info("[ADMIN] #{current_user.username} bulk-imported spam_numbers added=#{added} updated=#{updated} invalid=#{invalid}")
      { added: added, updated: updated, invalid: invalid }
    end
  end
end
