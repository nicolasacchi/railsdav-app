require "csv"
require "json"

module Contacts
  class Exporter
    CSV_HEADERS = %w[
      uid full_name first_name last_name middle_name name_prefix name_suffix
      nickname pronouns
      email_1 email_2 email_3 phone_1 phone_2 phone_3
      organization title role note
      birthday anniversary
      url_1 url_2 url_3
      address_1_street address_1_city address_1_state address_1_zip address_1_country
      categories
    ].freeze

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
          urls = d.urls.map { |u| u[:value] }
          addr = d.addresses.first || {}

          csv << [
            d.uid,
            d.full_name,
            d.first_name,
            d.last_name,
            d.middle_name,
            d.name_prefix,
            d.name_suffix,
            d.nickname,
            d.pronouns,
            emails[0], emails[1], emails[2],
            phones[0], phones[1], phones[2],
            d.organization,
            d.title,
            d.role,
            d.note,
            d.birthday,
            d.anniversary,
            urls[0], urls[1], urls[2],
            addr[:street], addr[:city], addr[:state], addr[:zip], addr[:country],
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
          middle_name: d.middle_name,
          name_prefix: d.name_prefix,
          name_suffix: d.name_suffix,
          nickname: d.nickname,
          pronouns: d.pronouns,
          gender: d.gender,
          emails: d.emails.map { |e| e[:value] },
          phones: d.phones.map { |p| p[:value] },
          impp: d.impp.map { |im| { type: im[:type], value: im[:value] } },
          social_profiles: d.social_profiles.map { |sp| { type: sp[:type], value: sp[:value] } },
          organization: d.organization,
          title: d.title,
          role: d.role,
          note: d.note,
          birthday: d.birthday,
          anniversary: d.anniversary,
          urls: d.urls.map { |u| u[:value] },
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
