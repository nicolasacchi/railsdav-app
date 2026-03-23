FactoryBot.define do
  factory :addressbook do
    user
    sequence(:uri) { |n| "addressbook#{n}" }
    displayname { "My Contacts" }
  end
end
