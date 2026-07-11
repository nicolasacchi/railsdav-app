class User < ApplicationRecord
  has_secure_password

  has_many :addressbooks, dependent: :destroy
  has_many :addressbook_shares, dependent: :destroy
  # Only accepted shares grant access — a pending invitation must not expose the
  # book until the invitee clicks Accept.
  has_many :accepted_addressbook_shares, -> { accepted }, class_name: "AddressbookShare"
  has_many :shared_addressbooks, through: :accepted_addressbook_shares, source: :addressbook

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

  # --- Per-tenant callscreen API token -------------------------------------
  # An opt-in alternative to the shared global CALLSCREEN_API_TOKEN. Stored only
  # as a SHA-256 digest; the plaintext is returned once at generation time. A
  # request bearing this token is PINNED to this user and cannot address other
  # tenants via ?username=, so a leaked per-tenant token exposes only one book.

  def self.api_token_digest(token)
    Digest::SHA256.hexdigest(token.to_s)
  end

  def self.authenticate_api_token(token)
    return nil if token.blank?
    find_by(api_token_digest: api_token_digest(token))
  end

  def regenerate_api_token!
    plaintext = SecureRandom.urlsafe_base64(32)
    update!(api_token_digest: self.class.api_token_digest(plaintext))
    plaintext
  end

  def revoke_api_token!
    update!(api_token_digest: nil)
  end

  def api_token?
    api_token_digest.present?
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
