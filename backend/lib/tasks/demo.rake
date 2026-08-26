DEMO_FIRST_NAMES = %w[
  James Mary Patricia Robert Jennifer Michael Linda William Barbara David
  Elizabeth Richard Susan Joseph Jessica Thomas Sarah Charles Karen Nancy
  Priya Rahul Ananya Arjun Mei Zhang Wei Liu Min Chen
  Fatima Ahmed Omar Layla Hassan Ibrahim Aisha Yusuf Zara
  Carlos Maria Jose Ana Luis Rosa Pedro Carmen Francisco Isabel
  Yuki Hiroshi Sakura Kenji Akiko Takeshi Yuna Jae-won Sung-min Ji-young
].freeze

DEMO_LAST_NAMES = %w[
  Smith Johnson Williams Brown Jones Garcia Miller Davis Wilson Martinez
  Anderson Taylor Thomas Hernandez Moore Jackson Martin Lee Thompson White
  Kumar Sharma Singh Gupta Patel Mehta Joshi Nair Pillai Reddy
  Wang Li Zhang Liu Chen Yang Huang Zhou Wu Xu
  Kim Park Lee Choi Jung Kang Yoon Lim Song Han
  Müller Schmidt Fischer Weber Becker Hoffmann Schulz Braun Richter Klein
  Dupont Martin Bernard Moreau Simon Laurent Michel Garcia Roux David
].freeze

DEMO_DEPARTMENTS = {
  'Engineering' => {
    titles: ['Software Engineer', 'Senior Software Engineer', 'Staff Engineer',
             'Principal Engineer', 'Engineering Manager'],
    levels: %w[L3 L4 L5 L6]
  },
  'Sales' => {
    titles: ['Sales Development Rep', 'Account Executive', 'Senior AE',
             'Enterprise AE', 'Sales Director'],
    levels: %w[L2 L3 L4 L5 L6]
  },
  'Finance' => {
    titles: ['Financial Analyst', 'Senior Financial Analyst',
             'Financial Controller', 'Finance Manager', 'CFO'],
    levels: %w[L3 L4 L5 L6]
  },
  'HR' => {
    titles: ['HR Coordinator', 'HR Business Partner', 'Senior HRBP', 'HR Director'],
    levels: %w[L2 L3 L4 L5]
  },
  'Design' => {
    titles: ['UX Researcher', 'Product Designer', 'Senior Product Designer', 'Design Lead'],
    levels: %w[L3 L4 L5]
  },
  'Operations' => {
    titles: ['Operations Analyst', 'Operations Manager', 'Senior Operations Manager',
             'VP Operations'],
    levels: %w[L3 L4 L5 L6]
  }
}.freeze

DEMO_DEPT_WEIGHTS = { 'Engineering' => 35, 'Sales' => 20, 'Operations' => 15,
                      'Finance' => 15, 'HR' => 10, 'Design' => 5 }.freeze

DEMO_CURRENCY_RANGE = {
  'USD' => (60_000..220_000),
  'GBP' => (45_000..160_000),
  'EUR' => (50_000..150_000),
  'INR' => (800_000..4_500_000),
  'JPY' => (4_000_000..18_000_000),
  'SGD' => (70_000..200_000),
  'AUD' => (75_000..190_000),
  'CAD' => (65_000..175_000),
  'CHF' => (90_000..200_000),
  'BRL' => (80_000..350_000),
  'MXN' => (300_000..1_200_000),
  'SEK' => (400_000..1_200_000),
  'NOK' => (450_000..1_400_000),
  'DKK' => (400_000..1_200_000),
  'ZAR' => (300_000..1_500_000),
  'HKD' => (300_000..1_200_000),
  'AED' => (120_000..550_000),
  'KRW' => (40_000_000..130_000_000),
  'TWD' => (800_000..3_500_000),
  'PLN' => (60_000..250_000)
}.freeze

# [country_code, currency] pairs weighted toward high-headcount markets.
DEMO_COUNTRY_POOL = [
  %w[US USD], %w[US USD], %w[US USD], %w[US USD],
  %w[GB GBP], %w[GB GBP],
  %w[DE EUR], %w[DE EUR],
  %w[IN INR], %w[IN INR],
  %w[JP JPY], %w[FR EUR], %w[NL EUR], %w[CA CAD],
  %w[AU AUD], %w[SG SGD], %w[CH CHF], %w[BR BRL],
  %w[MX MXN], %w[SE SEK], %w[NO NOK], %w[DK DKK],
  %w[ZA ZAR], %w[HK HKD], %w[AE AED], %w[KR KRW],
  %w[TW TWD], %w[PL PLN], %w[IE EUR], %w[ES EUR]
].freeze

namespace :demo do
  desc 'Generate a 10,000-row demo import CSV for evaluator handoff.'
  task generate_import_csv: :environment do
    require 'csv'

    srand(2025)
    dept_pool = DEMO_DEPT_WEIGHTS.flat_map { |dept, w| [dept] * w }
    output_path = Rails.root.join('../demo_import_10k.csv')

    CSV.open(output_path, 'w') do |csv|
      csv << %w[employee_number first_name last_name email department_name
                job_title job_level country_code hire_date salary_amount salary_currency]

      10_000.times do |i|
        n               = i + 1
        dept            = dept_pool.sample
        info            = DEMO_DEPARTMENTS[dept]
        title           = info[:titles].sample
        level           = info[:levels].sample
        country, currency = DEMO_COUNTRY_POOL.sample
        range           = DEMO_CURRENCY_RANGE[currency] || (60_000..220_000)
        amount          = rand(range)
        first           = DEMO_FIRST_NAMES.sample
        last            = DEMO_LAST_NAMES.sample
        hire            = Date.new(2015, 1, 1) + rand(3650)
        email           = "imp.#{n.to_s.rjust(5, '0')}@acme-corp.com"

        csv << [
          "IMP-#{n.to_s.rjust(5, '0')}",
          first, last, email,
          dept, title, level, country,
          hire.iso8601,
          amount, currency
        ]
      end
    end

    puts "demo_import_10k.csv written (10,000 rows) → #{output_path}"
  end
end
