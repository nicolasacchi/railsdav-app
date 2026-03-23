FactoryBot.define do
  factory :contact do
    addressbook
    sequence(:uid) { |n| "uid-#{n}@example.com" }
    sequence(:uri) { |n| "contact-#{n}.vcf" }
    vcard_data do
      <<~VCARD
        BEGIN:VCARD
        VERSION:3.0
        UID:#{uid}
        FN:Test Contact
        N:Contact;Test;;;
        END:VCARD
      VCARD
    end
  end
end
