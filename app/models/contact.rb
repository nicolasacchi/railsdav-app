require "e2ee/detection"

class Contact < ApplicationRecord
  belongs_to :addressbook
  has_many :contact_group_memberships, dependent: :destroy
  has_many :contact_groups, through: :contact_group_memberships
  has_many :contact_phone_numbers, dependent: :destroy
  has_one :owned_group, class_name: "ContactGroup", foreign_key: :group_contact_id, dependent: :nullify

  validates :uri, presence: true, uniqueness: { scope: :addressbook_id }
  validates :uid, presence: true
  validates :vcard_data, presence: true
  validates :etag, presence: true
  validates :call_screening_policy,
            inclusion: { in: Addressbook::CALL_SCREENING_POLICIES },
            allow_nil: true
  validate :call_screening_policy_blank_when_encrypted

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
  after_save :sync_phone_numbers, if: -> { saved_change_to_vcard_data? && !encrypted? && !bootstrap_vcard? }

  def effective_screening_policy
    call_screening_policy.presence || addressbook&.call_screening_policy || "screen"
  end

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

  def call_screening_policy_blank_when_encrypted
    return unless encrypted? && call_screening_policy.present?
    errors.add(:call_screening_policy, "cannot be set on encrypted contacts")
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
      raw_name = (parsed&.full_name.presence || "").to_s
      self.cached_display_name = raw_name.gsub(/[\r\n\x00-\x1F\x7F]/, "").strip.first(200)
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

  def sync_phone_numbers
    parsed = Vcard::Parser.parse(raw_vcard_data)
    raw_entries = Array(parsed&.phones)

    default_country = ENV.fetch("PHONE_DEFAULT_COUNTRY", "IT")
    rows = raw_entries.filter_map do |entry|
      raw_value = entry.is_a?(Hash) ? entry[:value] : entry.to_s
      next if raw_value.blank?

      parsed_phone = Phonelib.parse(raw_value, default_country)
      next unless parsed_phone.valid?

      {
        e164: parsed_phone.e164,
        raw: raw_value,
        phone_type: entry.is_a?(Hash) ? entry[:type] : nil
      }
    end.uniq { |row| row[:e164] }

    contact_phone_numbers.delete_all
    rows.each { |row| contact_phone_numbers.create!(row) }
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
