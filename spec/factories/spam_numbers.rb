FactoryBot.define do
  factory :spam_number do
    sequence(:phone) { |n| "+39333111#{n.to_s.rjust(4, '0')}" }
    source { "manual" }
    first_reported_at { Time.current }
    last_seen_at      { first_reported_at }
    report_count      { 1 }
  end
end
