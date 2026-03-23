FactoryBot.define do
  factory :user do
    sequence(:username) { |n| "user#{n}" }
    password { "password123" }
    sequence(:email) { |n| "user#{n}@example.com" }

    trait :admin do
      admin { true }
    end
  end
end
