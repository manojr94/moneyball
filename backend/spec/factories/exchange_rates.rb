FactoryBot.define do
  factory :exchange_rate do
    currency { 'EUR' }
    rate_to_usd { '1.08' }
    sequence(:effective_date) { |n| Date.new(2024, 1, 1) + (n - 1).days }
  end
end
