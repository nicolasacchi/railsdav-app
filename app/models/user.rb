class User < ApplicationRecord
  has_secure_password

  has_many :addressbooks, dependent: :destroy
  has_many :addressbook_shares, dependent: :destroy
  has_many :shared_addressbooks, through: :addressbook_shares, source: :addressbook

  scope :recent, -> { order(created_at: :desc) }

  normalizes :email, with: ->(e) { e.strip.downcase }

  validates :username, presence: true,
                       uniqueness: { case_sensitive: false },
                       format: { with: /\A[a-z0-9._-]+\z/i, message: "only allows letters, numbers, dots, hyphens, underscores" }
  validates :email, presence: true,
                    uniqueness: { case_sensitive: false },
                    format: { with: URI::MailTo::EMAIL_REGEXP }
  validates :password, length: { minimum: 8 }, allow_nil: true

  before_validation :generate_username_from_email, on: :create
  after_create :create_default_addressbook
  after_create :claim_pending_invitations

  def admin?
    admin == true
  end

  private

  def generate_username_from_email
    return if username.present? || email.blank?

    base = email.split("@").first.downcase.gsub(/[^a-z0-9._-]/, "-").truncate(30, omission: "")
    base = "user" if base.blank?

    candidate = base
    counter = 1
    while User.where.not(id: id).exists?(username: candidate)
      candidate = "#{base}-#{counter}"
      counter += 1
    end
    self.username = candidate
  end

  def create_default_addressbook
    addressbooks.create!(uri: "default", displayname: "Contacts", description: "Default address book")
  end

  def claim_pending_invitations
    AddressbookShare.where(invited_email: email, status: "pending").find_each do |share|
      share.update!(user_id: id, status: "accepted", invitation_token: nil)
    end
  end
end
