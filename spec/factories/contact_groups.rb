FactoryBot.define do
  factory :contact_group do
    addressbook
    sequence(:name) { |n| "Group #{n}" }
  end
end
