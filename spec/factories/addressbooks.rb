FactoryBot.define do
  factory :addressbook do
    user
    sequence(:uri) { |n| "addressbook#{n}" }
    displayname { "My Contacts" }

    after(:create) do |addressbook|
      addressbook.update_column(:dav_password_digest, BCrypt::Password.create(DAV_TEST_PASSWORD))
    end
  end
end
