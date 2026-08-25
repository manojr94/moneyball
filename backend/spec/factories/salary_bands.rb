FactoryBot.define do
  factory :salary_band do
    association :pay_zone
    job_title        { 'Software Engineer' }
    job_level        { 'L3' }
    currency         { 'USD' }
    min_minor_units  { 80_000_00 }
    mid_minor_units  { 100_000_00 }
    max_minor_units  { 130_000_00 }
    effective_from   { 2.years.ago.to_date }
    effective_to     { nil }

    trait :current do
      effective_from { 2.years.ago.to_date }
      effective_to   { nil }
    end

    trait :closed do
      effective_from { 3.years.ago.to_date }
      effective_to   { 2.years.ago.to_date }
    end
  end
end
