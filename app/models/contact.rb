require "e2ee/detection"

class Contact < ApplicationRecord
  belongs_to :addressbook
  has_many :contact_group_memberships, dependent: :destroy
  has_many :contact_groups, through: :contact_group_memberships
  has_one :owned_group, class_name: "ContactGroup", foreign_key: :group_contact_id, dependent: :nullify

  validates :uri, presence: true, uniqueness: { scope: :addressbook_id }
  validates :uid, presence: true
  validates :vcard_data, presence: true
  validates :etag, presence: true

  scope :individuals, -> { where(kind: "individual") }
  scope :group_vcards, -> { where(kind: "group") }
  scope :display_order, -> { order(Arel.sql("CASE WHEN cached_display_name = '' THEN 1 ELSE 0 END, LOWER(cached_display_name)")) }
  scope :encrypted, -> { where(encrypted: true) }
  scope :unencrypted, -> { where(encrypted: false) }
  scope :non_bootstrap, -> { where.not(uid: E2ee::Detection::BOOTSTRAP_UID) }

  before_validation :compute_etag, if: -> { vcard_data.present? && vcard_data_changed? }
  before_validation :extract_uid, if: -> { vcard_data.present? && vcard_data_changed? && !encrypted? }
  before_validation :cache_display_name, if: -> { vcard_data.present? && vcard_data_changed? }
  after_save :sync_groups_from_vcard, if: -> { saved_change_to_vcard_data? && !encrypted? && !bootstrap_vcard? }

  def bootstrap_vcard?
    uid == E2ee::Detection::BOOTSTRAP_UID
  end

  # Base64 encode/decode for encrypted binary storage in text column
  def vcard_data
    raw = read_attribute(:vcard_data)
    return raw unless encrypted? && raw.present? && !raw.start_with?("BEGIN:VCARD")
    Base64.strict_decode64(raw)
  rescue ArgumentError
    raw
  end

  def vcard_data=(val)
    if encrypted? && val.present? && !val.b.start_with?("BEGIN:VCARD")
      write_attribute(:vcard_data, Base64.strict_encode64(val))
    else
      write_attribute(:vcard_data, val)
    end
  end

  # Read raw stored value (Base64 for encrypted) for ETag computation
  def raw_vcard_data
    read_attribute(:vcard_data)
  end

  private

  def compute_etag
    self.etag = "\"#{Digest::SHA256.hexdigest(raw_vcard_data)}\""
  end

  def extract_uid
    if (match = raw_vcard_data.match(/^UID(?:;[^:]*)?:(.+)$/i))
      self.uid = match[1].strip
    end
  end

  def cache_display_name
    if encrypted?
      self.cached_display_name = "[Encrypted]"
      self.kind = "individual"
    else
      parsed = Vcard::Parser.parse(raw_vcard_data)
      self.cached_display_name = parsed&.full_name.presence || ""
      self.kind = parsed&.kind || "individual"
    end
  end

  def sync_groups_from_vcard
    parsed = Vcard::Parser.parse(raw_vcard_data)
    return unless parsed

    if kind == "group"
      sync_group_vcard(parsed)
    else
      sync_categories(parsed)
    end
  end

  def sync_group_vcard(parsed)
    group_name = parsed.full_name.presence || "Unnamed Group"
    group = addressbook.contact_groups.find_or_create_by!(name: group_name)
    group.update!(group_contact_id: id) unless group.group_contact_id == id

    member_uids = parsed.member_uids || []
    member_contacts = addressbook.contacts.where(uid: member_uids).where.not(id: id)
    group.contact_ids = member_contacts.pluck(:id)
  end

  def sync_categories(parsed)
    categories = parsed.categories || []
    if categories.any?
      groups = categories.map do |cat_name|
        addressbook.contact_groups.find_or_create_by!(name: cat_name) do |g|
          g.name = cat_name
        end
      end
      self.contact_group_ids = groups.map(&:id)
    else
      self.contact_group_ids = []
    end
  end
end
