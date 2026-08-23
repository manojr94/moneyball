FactoryBot.define do
  factory :department do
    sequence(:name) { |n| "Department #{n}" }
    slug { name&.downcase&.gsub(/\s+/, '-') }
  end
end
