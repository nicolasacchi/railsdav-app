# Shared helpers for the callscreen write endpoints that locate (or create) a
# contact in the resolved tenant's OWN books by phone number. Assumes @api_user
# has been set (see ResolvesApiUser).
module ResolvesContactByPhone
  extend ActiveSupport::Concern

  private

  # Strictest-policy match within the user's OWN books, mirroring PhoneLookup so
  # a policy write targets the same contact a subsequent lookup would surface.
  def existing_contact_for(e164)
    contacts = ContactPhoneNumber
      .where(e164: e164)
      .joins(contact: :addressbook)
      .where(addressbooks: { user_id: @api_user.id })
      .includes(contact: :addressbook)
      .map(&:contact)
      .uniq
    contacts.min_by { |c| Contacts::PhoneLookup::POLICY_RANK.fetch(c.effective_screening_policy, 99) }
  end

  def target_addressbook_for_api_user
    @api_user.addressbooks.find_by(uri: "default") || @api_user.addressbooks.order(:id).first
  end
end
