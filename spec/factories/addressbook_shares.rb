FactoryBot.define do
  factory :addressbook_share do
    addressbook
    user
    permission { "read" }
    status { "accepted" }

    trait :write do
      permission { "write" }
    end

    trait :public_link do
      user { nil }
      permission { "read" }
      token { SecureRandom.urlsafe_base64(24) }
    end

    trait :pending do
      status { "pending" }
      invited_email { user&.email || "invited@example.com" }
      invitation_token { SecureRandom.urlsafe_base64(24) }
      invitation_sent_at { Time.current }
    end

    trait :pending_new_user do
      user { nil }
      status { "pending" }
      sequence(:invited_email) { |n| "newuser#{n}@example.com" }
      invitation_token { SecureRandom.urlsafe_base64(24) }
      invitation_sent_at { Time.current }
    end
  end
end
