FactoryBot.define do
  factory :user do
    sequence(:email) { |n| "user#{n}@example.com" }
    name { 'Test User' }
    password { 'password123' }
    role { 'viewer' }
    active { true }

    trait :hr_admin do
      name { 'HR Admin' }
      role { 'hr_admin' }
    end

    trait :viewer do
      role { 'viewer' }
    end

    trait :inactive do
      active { false }
    end
  end
end
