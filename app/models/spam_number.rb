class SpamNumber < ApplicationRecord
  # Cross-tenant global blocklist of known-spam numbers. One row per
  # phone (E.164), regardless of how many tenants reported it. The
  # `source` column distinguishes operator (ntfy / admin) reports from
  # imported feeds, but the numeric weight is `report_count`.

  SOURCES_WHITELIST = %w[ntfy_report manual].freeze
  FEED_SOURCE_FORMAT = /\Afeed:[a-z0-9_\-]{1,40}\z/

  validates :phone, presence: true, uniqueness: true
  validates :source, presence: true
  validate  :source_is_known
  validate  :phone_is_valid_e164

  before_validation :normalize_phone
  before_validation :default_timestamps, on: :create

  scope :recent, -> { order(last_seen_at: :desc) }

  # Atomic upsert. Idempotent: a re-report bumps the counter and
  # `last_seen_at` but never resets `first_reported_at` or
  # `submitted_by_username` (which name the *first* reporter for audit).
  # Single-row lock — uniqueness on phone serializes contention so the
  # extra blocking is bounded to concurrent reports of the same number.
  def self.upsert_report!(phone:, source:, submitted_by_username: nil, notes: nil)
    e164 = normalize_e164(phone)
    raise ArgumentError, "invalid phone" if e164.nil?

    existing = lock.find_by(phone: e164)
    if existing
      existing.with_lock do
        existing.report_count += 1
        existing.last_seen_at = Time.current
        existing.notes = notes if notes.present? && existing.notes.blank?
        existing.save!
      end
      existing
    else
      now = Time.current
      create!(
        phone: e164,
        source: source,
        submitted_by_username: submitted_by_username,
        notes: notes,
        report_count: 1,
        first_reported_at: now,
        last_seen_at: now
      )
    end
  rescue ActiveRecord::RecordNotUnique
    # Lost the race with a parallel insert — retry once.
    existing = find_by!(phone: e164)
    existing.with_lock do
      existing.report_count += 1
      existing.last_seen_at = Time.current
      existing.save!
    end
    existing
  end

  def self.normalize_e164(raw)
    return nil if raw.blank?
    parsed = Phonelib.parse(raw.to_s, ENV.fetch("PHONE_DEFAULT_COUNTRY", "IT"))
    parsed.valid? ? parsed.e164 : nil
  end

  private

  def normalize_phone
    return if phone.blank?
    e164 = self.class.normalize_e164(phone)
    self.phone = e164 if e164
  end

  def phone_is_valid_e164
    return if phone.blank?
    parsed = Phonelib.parse(phone.to_s, ENV.fetch("PHONE_DEFAULT_COUNTRY", "IT"))
    errors.add(:phone, "is not a valid phone number") unless parsed.valid?
  end

  def source_is_known
    return if source.blank?
    return if SOURCES_WHITELIST.include?(source)
    return if source.match?(FEED_SOURCE_FORMAT)
    errors.add(:source, "must be one of #{SOURCES_WHITELIST.join(', ')} or 'feed:<id>'")
  end

  def default_timestamps
    self.first_reported_at ||= Time.current
    self.last_seen_at      ||= first_reported_at
  end
end
