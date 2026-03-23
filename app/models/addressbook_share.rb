class AddressbookShare < ApplicationRecord
  belongs_to :addressbook
  belongs_to :user, optional: true

  normalizes :invited_email, with: ->(e) { e&.strip&.downcase }

  validates :permission, inclusion: { in: %w[read write] }
  validates :status, inclusion: { in: %w[pending accepted] }
  validates :addressbook_id, uniqueness: { scope: :user_id }, if: -> { user_id.present? && accepted? }
  validates :token, uniqueness: true, allow_nil: true
  validates :invitation_token, uniqueness: true, allow_nil: true
  validate :public_links_must_be_read_only

  before_create :generate_token, if: -> { public_link_candidate? }
  before_create :generate_invitation_token, if: -> { pending? && invitation_token.nil? }
  before_create :set_invitation_expiry, if: -> { pending? }

  scope :for_user, ->(user) { where(user: user, status: "accepted") }
  scope :public_links, -> { where(user_id: nil, invited_email: nil).where.not(token: nil) }
  scope :accepted, -> { where(status: "accepted") }
  scope :pending, -> { where(status: "pending") }
  scope :pending_for_email, ->(email) { pending.where(invited_email: email&.strip&.downcase) }

  def public_link?
    user_id.nil? && invited_email.nil? && token.present?
  end

  def writable?
    permission == "write"
  end

  def accepted?
    status == "accepted"
  end

  def pending?
    status == "pending"
  end

  def invitation_expired?
    pending? && invitation_expires_at.present? && invitation_expires_at < Time.current
  end

  def accept!
    update!(status: "accepted", invitation_token: nil)
  end

  def regenerate_invitation_token!
    update!(invitation_token: SecureRandom.urlsafe_base64(24))
  end

  private

  def public_link_candidate?
    user_id.nil? && invited_email.nil? && token.nil?
  end

  def generate_token
    loop do
      self.token = SecureRandom.urlsafe_base64(24)
      break unless AddressbookShare.exists?(token: token)
    end
  end

  def generate_invitation_token
    loop do
      self.invitation_token = SecureRandom.urlsafe_base64(24)
      break unless AddressbookShare.exists?(invitation_token: invitation_token)
    end
  end

  def set_invitation_expiry
    self.invitation_expires_at ||= 7.days.from_now
  end

  def public_links_must_be_read_only
    if public_link? && permission != "read"
      errors.add(:permission, "must be read for public links")
    end
  end
end
