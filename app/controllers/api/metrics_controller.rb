module Api
  # Observability surface for callscreen (or a monitoring scrape). Bearer-gated
  # like the rest of the internal API. Cheap indexed counts only.
  class MetricsController < BaseController
    def show
      render json: {
        ok: true,
        users: User.count,
        addressbooks: Addressbook.count,
        contacts: {
          total: Contact.count,
          individuals: Contact.individuals.count,
          encrypted: Contact.encrypted.count
        },
        phone_numbers: ContactPhoneNumber.count,
        spam: {
          total: SpamNumber.count,
          active: SpamNumber.active.count
        }
      }
    end
  end
end
