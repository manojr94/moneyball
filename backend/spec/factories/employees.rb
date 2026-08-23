EMPLOYEE_COUNTRY_SEQUENCE = Enumerator.new do |e|
  letters = ('A'..'Z').to_a
  n = 0
  loop do
    e << "#{letters[(n / 26) % 26]}#{letters[n % 26]}"
    n += 1
  end
end

FactoryBot.define do
  factory :employee do
    sequence(:employee_number) { |n| "EMP#{n.to_s.rjust(5, '0')}" }
    first_name { 'Jane' }
    last_name  { 'Doe' }
    sequence(:email) { |n| "employee#{n}@example.com" }
    association :department
    job_title { 'Software Engineer' }
    job_level { 'L3' }
    hire_date { Date.new(2020, 1, 1) }
    status { 'active' }
    country_code { EMPLOYEE_COUNTRY_SEQUENCE.next }

    # Country must be persisted even in build-strategy specs because
    # Employee#ensure_country_exists and belongs_to :country both query the DB.
    after(:build) do |employee|
      next if employee.country_code.blank?
      next if Country.exists?(code: employee.country_code)

      create(:country, code: employee.country_code)
    end
  end
end
