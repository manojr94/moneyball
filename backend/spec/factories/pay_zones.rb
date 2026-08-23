FactoryBot.define do
  factory :pay_zone do
    sequence(:name) { |n| "Pay Zone #{n}" }
    slug { name&.downcase&.gsub(/\s+/, '-') }
  end
end
