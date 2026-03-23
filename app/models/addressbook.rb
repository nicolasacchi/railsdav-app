class Addressbook < ApplicationRecord
  belongs_to :user
  has_many :contacts, dependent: :destroy
  has_many :sync_changes, dependent: :destroy
  has_many :contact_groups, dependent: :destroy
  has_many :shares, class_name: "AddressbookShare", dependent: :destroy
  has_many :shared_users, through: :shares, source: :user

  validates :uri, presence: true,
                  uniqueness: { scope: :user_id },
                  format: { with: /\A[a-z0-9_-]+\z/i }
  validates :displayname, presence: true

  before_create :set_initial_dav_password

  def regenerate_dav_password!
    plaintext = SecureRandom.urlsafe_base64(18)
    update!(dav_password_digest: BCrypt::Password.create(plaintext))
    plaintext
  end

  def authenticate_dav(password)
    return false if dav_password_digest.blank?
    BCrypt::Password.new(dav_password_digest) == password
  end

  def increment_sync!
    with_lock do
      increment!(:ctag)
      increment!(:sync_token)
    end
  end

  def record_sync_change!(uri:, change_type:)
    increment_sync!
    sync_changes.create!(uri: uri, sync_token: sync_token, change_type: change_type)
  end

  def sync_token_url
    host = Railsdav.site_url || "localhost"
    "http://#{host}/ns/sync/#{sync_token}"
  end

  def self.parse_sync_token(token_url)
    match = token_url&.match(%r{/ns/sync/(\d+)\z})
    match ? match[1].to_i : nil
  end

  private

  def set_initial_dav_password
    if dav_password_digest.blank?
      plaintext = SecureRandom.urlsafe_base64(18)
      self.dav_password_digest = BCrypt::Password.create(plaintext)
      @initial_dav_password = plaintext
    end
  end
end
