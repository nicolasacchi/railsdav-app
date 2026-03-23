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

  before_create :generate_dav_password

  def regenerate_dav_password!
    update!(dav_password: SecureRandom.urlsafe_base64(18))
  end

  def increment_sync!
    with_lock do
      increment!(:ctag)
      increment!(:sync_token)
    end
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

  def generate_dav_password
    self.dav_password ||= SecureRandom.urlsafe_base64(18)
  end
end
