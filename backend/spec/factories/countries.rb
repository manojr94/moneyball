FactoryBot.define do
  factory :country do
    # Generate unique 2-letter codes: AA, AB, AC, ... AZ, BA, BB, ...
    sequence(:code) do |n|
      letters = ('A'..'Z').to_a
      first = letters[(n / 26) % 26]
      second = letters[n % 26]
      "#{first}#{second}"
    end
    name { "Country #{code}" }
    default_currency { 'USD' }
    region { 'na' }
    needs_review { false }
    association :pay_zone
  end
end
