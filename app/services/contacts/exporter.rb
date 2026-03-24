require "csv"
require "json"

module Contacts
  class Exporter
    CSV_HEADERS = %w[uid full_name first_name last_name email_1 email_2 email_3 phone_1 phone_2 phone_3 organization title note categories].freeze

    def self.to_vcf(contacts)
      contacts.select { |c| (c.kind == "individual" || c.encrypted?) && !c.bootstrap_vcard? }
              .map(&:vcard_data).join("\r\n")
    end

    def self.to_csv(contacts)
      bom = "\xEF\xBB\xBF"
      bom + CSV.generate do |csv|
        csv << CSV_HEADERS
        contacts.each do |contact|
          next unless contact.kind == "individual"
          next if contact.encrypted?
          d = Vcard::Parser.parse(contact.vcard_data)
          next unless d

          emails = d.emails.map { |e| e[:value] }
          phones = d.phones.map { |p| p[:value] }

          csv << [
            d.uid,
            d.full_name,
            d.first_name,
            d.last_name,
            emails[0],
            emails[1],
            emails[2],
            phones[0],
            phones[1],
            phones[2],
            d.organization,
            d.title,
            d.note,
            d.categories.join(", ")
          ]
        end
      end
    end

    def self.to_json(contacts)
      data = contacts.filter_map do |contact|
        next unless contact.kind == "individual"
        next if contact.encrypted?
        d = Vcard::Parser.parse(contact.vcard_data)
        next unless d

        {
          uid: d.uid,
          full_name: d.full_name,
          first_name: d.first_name,
          last_name: d.last_name,
          emails: d.emails.map { |e| e[:value] },
          phones: d.phones.map { |p| p[:value] },
          organization: d.organization,
          title: d.title,
          note: d.note,
          categories: d.categories,
          addresses: d.addresses.map do |a|
            { type: a[:type], street: a[:street], city: a[:city], state: a[:state], zip: a[:zip], country: a[:country] }
          end
        }
      end

      JSON.pretty_generate(data)
    end
  end
end
