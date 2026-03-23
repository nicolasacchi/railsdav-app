FactoryBot.define do
  factory :user do
    sequence(:username) { |n| "user#{n}" }
    password { "password123" }
    sequence(:email) { |n| "user#{n}@example.com" }

    trait :admin do
      admin { true }
    end

    after(:create) do |user|
      user.addressbooks.update_all(dav_password_digest: BCrypt::Password.create(DAV_TEST_PASSWORD))
    end
  end
end
