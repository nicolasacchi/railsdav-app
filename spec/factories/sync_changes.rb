FactoryBot.define do
  factory :sync_change do
    addressbook
    sequence(:uri) { |n| "contact-#{n}.vcf" }
    sync_token { 1 }
    change_type { "created" }
  end
end
