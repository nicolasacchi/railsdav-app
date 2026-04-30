module Contacts
  class PhoneLookup
    Result = Struct.new(:contact, :policy, keyword_init: true)

    POLICY_RANK = { "block" => 0, "allow" => 1, "screen" => 2 }.freeze

    # Looks up the strictest-policy contact that owns +phone+ within +user+'s
    # OWN addressbooks. Shared addressbooks are intentionally excluded — the
    # screening policy belongs to the addressbook owner, not the share guest.
    def self.find_by_e164(phone, user:)
      return nil if user.nil?
      return nil if phone.blank? || !phone.is_a?(String)

      normalized = Phonelib.parse(phone, ENV.fetch("PHONE_DEFAULT_COUNTRY", "IT"))
      return nil unless normalized.valid?

      contacts = ContactPhoneNumber
        .where(e164: normalized.e164)
        .joins(contact: :addressbook)
        .where(addressbooks: { user_id: user.id })
        .includes(contact: :addressbook)
        .map(&:contact)
        .uniq
      return nil if contacts.empty?

      best = contacts.min_by { |c| POLICY_RANK.fetch(c.effective_screening_policy, 99) }
      Result.new(contact: best, policy: best.effective_screening_policy)
    end
  end
end
