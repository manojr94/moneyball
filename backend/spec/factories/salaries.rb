FactoryBot.define do
  factory :salary do
    association :employee
    amount_minor_units { 10_000_00 }
    currency { 'USD' }
    sequence(:effective_date) { |n| Date.new(2024, 1, 1) + (n - 1).days }
    reason { 'new_hire' }
    created_by_id { 1 }
  end
end
