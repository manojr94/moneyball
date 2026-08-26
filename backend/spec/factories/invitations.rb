FactoryBot.define do
  factory :invitation do
    used_at { nil }

    trait :used do
      used_at { 1.hour.ago }
    end
  end
end
