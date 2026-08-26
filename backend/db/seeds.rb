# db/seeds.rb
# Idempotent. Reference data uses find_or_create_by!; the 10k-employee block
# is skipped when the target count is already met.
# rubocop:disable Rails/SkipsModelValidations -- insert_all! is intentional here;
# all referenced rows are pre-seeded and no after_create hooks exist on Employee/Salary.

# ── Pay zones ─────────────────────────────────────────────────────────────────

ZONE_MAP = {
  'na' => 'North America',
  'latam' => 'Latin America',
  'emea' => 'EMEA',
  'apac' => 'APAC'
}.freeze

zone_records = ZONE_MAP.each_with_object({}) do |(region, name), acc|
  acc[region] = PayZone.find_or_create_by!(slug: "default-#{region}") { |z| z.name = name }
end

# ── Countries ─────────────────────────────────────────────────────────────────

country_data = YAML.load_file(Rails.root.join('db/data/countries.yml'))
country_data.each do |code, attrs|
  zone = zone_records[attrs['region']]
  Country.find_or_create_by!(code: code) do |c|
    c.name             = attrs['name']
    c.default_currency = attrs['default_currency']
    c.region           = attrs['region']
    c.pay_zone         = zone
    c.needs_review     = false
  end
end

# ── Departments ───────────────────────────────────────────────────────────────

DEPARTMENT_NAMES = %w[Engineering Design Finance HR Sales Operations].freeze

dept_records = DEPARTMENT_NAMES.index_with do |name|
  Department.find_or_create_by!(name: name) do |d|
    d.slug = name.downcase
  end
end

# ── Users ─────────────────────────────────────────────────────────────────────

User.find_or_create_by!(email: 'admin@example.com') do |u|
  u.name     = 'Admin User'
  u.password = 'password'
  u.role     = 'hr_admin'
  u.active   = true
end

User.find_or_create_by!(email: 'viewer@example.com') do |u|
  u.name     = 'Viewer User'
  u.password = 'password'
  u.role     = 'viewer'
  u.active   = true
end

# ── Exchange rates ─────────────────────────────────────────────────────────────
# Quarterly, 2020–2025. USD is injected by the analytics CTE and needs no row.

RATE_SERIES = {
  'EUR' => {
    Date.new(2020, 1, 1) => '1.12', Date.new(2020, 4, 1) => '1.09',
    Date.new(2020, 7, 1) => '1.13', Date.new(2020, 10, 1) => '1.17',
    Date.new(2021, 1, 1) => '1.21', Date.new(2021, 4, 1) => '1.18',
    Date.new(2021, 7, 1) => '1.18', Date.new(2021, 10, 1) => '1.16',
    Date.new(2022, 1, 1) => '1.13', Date.new(2022, 4, 1) => '1.08',
    Date.new(2022, 7, 1) => '1.02', Date.new(2022, 10, 1) => '0.98',
    Date.new(2023, 1, 1) => '1.07', Date.new(2023, 4, 1) => '1.09',
    Date.new(2023, 7, 1) => '1.09', Date.new(2023, 10, 1) => '1.06',
    Date.new(2024, 1, 1) => '1.09', Date.new(2024, 4, 1) => '1.07',
    Date.new(2024, 7, 1) => '1.08', Date.new(2024, 10, 1) => '1.10',
    Date.new(2025, 1, 1) => '1.03'
  },
  'GBP' => {
    Date.new(2020, 1, 1) => '1.31', Date.new(2020, 4, 1) => '1.24',
    Date.new(2020, 7, 1) => '1.25', Date.new(2020, 10, 1) => '1.29',
    Date.new(2021, 1, 1) => '1.37', Date.new(2021, 4, 1) => '1.38',
    Date.new(2021, 7, 1) => '1.39', Date.new(2021, 10, 1) => '1.36',
    Date.new(2022, 1, 1) => '1.35', Date.new(2022, 4, 1) => '1.30',
    Date.new(2022, 7, 1) => '1.22', Date.new(2022, 10, 1) => '1.12',
    Date.new(2023, 1, 1) => '1.21', Date.new(2023, 4, 1) => '1.24',
    Date.new(2023, 7, 1) => '1.27', Date.new(2023, 10, 1) => '1.22',
    Date.new(2024, 1, 1) => '1.27', Date.new(2024, 4, 1) => '1.25',
    Date.new(2024, 7, 1) => '1.28', Date.new(2024, 10, 1) => '1.30',
    Date.new(2025, 1, 1) => '1.26'
  },
  'JPY' => {
    Date.new(2020, 1, 1) => '0.00910', Date.new(2020, 4, 1) => '0.00930',
    Date.new(2020, 7, 1) => '0.00940', Date.new(2020, 10, 1) => '0.00960',
    Date.new(2021, 1, 1) => '0.00960', Date.new(2021, 4, 1) => '0.00910',
    Date.new(2021, 7, 1) => '0.00910', Date.new(2021, 10, 1) => '0.00880',
    Date.new(2022, 1, 1) => '0.00870', Date.new(2022, 4, 1) => '0.00770',
    Date.new(2022, 7, 1) => '0.00720', Date.new(2022, 10, 1) => '0.00680',
    Date.new(2023, 1, 1) => '0.00750', Date.new(2023, 4, 1) => '0.00750',
    Date.new(2023, 7, 1) => '0.00700', Date.new(2023, 10, 1) => '0.00670',
    Date.new(2024, 1, 1) => '0.00670', Date.new(2024, 4, 1) => '0.00650',
    Date.new(2024, 7, 1) => '0.00640', Date.new(2024, 10, 1) => '0.00660',
    Date.new(2025, 1, 1) => '0.00650'
  },
  'CAD' => {
    Date.new(2020, 1, 1) => '0.77', Date.new(2020, 4, 1) => '0.71',
    Date.new(2020, 7, 1) => '0.74', Date.new(2020, 10, 1) => '0.76',
    Date.new(2021, 1, 1) => '0.78', Date.new(2021, 4, 1) => '0.79',
    Date.new(2021, 7, 1) => '0.80', Date.new(2021, 10, 1) => '0.80',
    Date.new(2022, 1, 1) => '0.79', Date.new(2022, 4, 1) => '0.80',
    Date.new(2022, 7, 1) => '0.77', Date.new(2022, 10, 1) => '0.73',
    Date.new(2023, 1, 1) => '0.74', Date.new(2023, 4, 1) => '0.74',
    Date.new(2023, 7, 1) => '0.75', Date.new(2023, 10, 1) => '0.73',
    Date.new(2024, 1, 1) => '0.74', Date.new(2024, 4, 1) => '0.73',
    Date.new(2024, 7, 1) => '0.73', Date.new(2024, 10, 1) => '0.72',
    Date.new(2025, 1, 1) => '0.70'
  }
}.freeze

RATE_SERIES.each do |currency, dates|
  dates.each do |date, rate|
    ExchangeRate.find_or_create_by!(currency: currency, effective_date: date) do |r|
      r.rate_to_usd = rate
    end
  end
end

# ── Salary bands ──────────────────────────────────────────────────────────────
# Designer L4 is intentionally left uncovered so the coverage report is non-empty.

band_seed_date = Date.new(2024, 1, 1)

[
  { region: 'na',   title: 'Engineer', level: 'L3', currency: 'USD',
    min: 80_000_00,  mid: 100_000_00, max: 130_000_00 },
  { region: 'na',   title: 'Engineer', level: 'L5', currency: 'USD',
    min: 130_000_00, mid: 160_000_00, max: 200_000_00 },
  { region: 'emea', title: 'Engineer', level: 'L3', currency: 'EUR',
    min: 70_000_00,  mid: 90_000_00,  max: 115_000_00 },
  { region: 'emea', title: 'Engineer', level: 'L5', currency: 'EUR',
    min: 110_000_00, mid: 140_000_00, max: 180_000_00 },
  { region: 'apac', title: 'Engineer', level: 'L3', currency: 'JPY',
    min: 7_000_000,  mid: 9_000_000,  max: 12_000_000 },
  { region: 'apac', title: 'Engineer', level: 'L5', currency: 'JPY',
    min: 12_000_000, mid: 16_000_000, max: 20_000_000 }
].each do |b|
  zone = zone_records[b[:region]]
  SalaryBand.find_or_create_by!(
    pay_zone_id: zone.id,
    job_title: b[:title],
    job_level: b[:level],
    effective_from: band_seed_date
  ) do |sb|
    sb.currency         = b[:currency]
    sb.min_minor_units  = b[:min]
    sb.mid_minor_units  = b[:mid]
    sb.max_minor_units  = b[:max]
    sb.effective_to     = nil
  end
end

# ── 10k employees + ~120k salary rows ─────────────────────────────────────────
# Uses insert_all! — bypasses ActiveRecord callbacks intentionally (safe because
# all referenced countries and departments are pre-seeded above). The
# before_validation country-auto-create callback is not needed for seed data.
# insert_all! also bypasses after_create hooks; there are none on Employee or
# Salary today. Any future hook on these models must account for this path.

TARGET_EMPLOYEES = 10_000
SEED_BATCH       = 500

current_count = Employee.count
if current_count >= TARGET_EMPLOYEES
  Rails.logger.debug { "Seed: #{current_count} employees already present — skipping bulk insert." }
else
  Rails.logger.debug { "Seed: generating #{TARGET_EMPLOYEES - current_count} employees..." }

  srand(42)

  # Weighted country pool — only currencies with seeded exchange rates
  SEED_COUNTRIES = (
    ([{ code: 'US', currency: 'USD' }] * 30) +
    ([{ code: 'GB', currency: 'GBP' }] * 15) +
    ([{ code: 'DE', currency: 'EUR' }] * 12) +
    ([{ code: 'FR', currency: 'EUR' }] * 10) +
    ([{ code: 'JP', currency: 'JPY' }] * 10) +
    ([{ code: 'CA', currency: 'CAD' }] * 10) +
    ([{ code: 'NL', currency: 'EUR' }] *  8) +
    ([{ code: 'ES', currency: 'EUR' }] *  5)
  ).freeze

  TITLES   = %w[Engineer Designer Analyst Manager].freeze
  LEVELS   = %w[L1 L2 L3 L4 L5 L6].freeze
  STATUSES = ((['active'] * 80) + (['inactive'] * 15) + (['terminated'] * 5)).freeze

  FIRST_NAMES = %w[
    James Mary Robert Patricia John Jennifer Michael Barbara William Linda
    David Elizabeth Richard Susan Joseph Jessica Thomas Sarah Charles Karen
    Christopher Lisa Daniel Nancy Matthew Betty Anthony Margaret Mark Sandra
    Donald Ashley Steven Dorothy Paul Kimberly Andrew Emily Joshua Donna
    Kenneth Michelle Kevin Carol Brian Amanda George Melissa Edward Deborah
  ].freeze

  LAST_NAMES = %w[
    Smith Johnson Williams Brown Jones Garcia Miller Davis Wilson Anderson
    Taylor Thomas Hernandez Moore Martin Jackson Thompson White Lopez Harris
    Sanchez Clark Ramirez Lewis Robinson Walker Perez Hall Young Allen
    King Wright Scott Torres Nguyen Hill Flores Green Adams Nelson Baker
    Rivera Campbell Mitchell Carter Roberts Gomez Phillips Evans Turner Morgan
  ].freeze

  # Salary starting ranges in major units per currency and level
  SALARY_RANGES = {
    'USD' => { 'L1' => [50_000, 65_000],  'L2' => [65_000, 85_000],
               'L3' => [85_000, 115_000], 'L4' => [110_000, 145_000],
               'L5' => [140_000, 185_000], 'L6' => [175_000, 230_000] },
    'GBP' => { 'L1' => [38_000, 50_000],  'L2' => [50_000, 68_000],
               'L3' => [68_000, 90_000],  'L4' => [88_000, 115_000],
               'L5' => [110_000, 148_000], 'L6' => [140_000, 185_000] },
    'EUR' => { 'L1' => [42_000, 55_000],  'L2' => [55_000, 72_000],
               'L3' => [72_000, 96_000],  'L4' => [92_000, 120_000],
               'L5' => [118_000, 155_000], 'L6' => [148_000, 195_000] },
    'JPY' => { 'L1' => [4_000_000, 5_500_000], 'L2' => [5_500_000, 7_000_000],
               'L3' => [7_000_000, 9_500_000],   'L4' => [9_000_000, 12_000_000],
               'L5' => [12_000_000, 16_000_000], 'L6' => [15_000_000, 20_000_000] },
    'CAD' => { 'L1' => [58_000, 75_000],  'L2' => [75_000, 98_000],
               'L3' => [98_000, 130_000], 'L4' => [125_000, 165_000],
               'L5' => [160_000, 210_000], 'L6' => [200_000, 260_000] }
  }.freeze

  SUBUNIT = { 'USD' => 100, 'GBP' => 100, 'EUR' => 100, 'CAD' => 100, 'JPY' => 1 }.freeze
  RAISE_REASONS = %w[merit promotion role_change].freeze

  dept_ids   = dept_records.values.map(&:id)
  now        = Time.current
  next_num   = (Employee.maximum('CAST(SUBSTRING(employee_number FROM 4) AS INTEGER)') || 0) + 1

  # Build all employee attribute rows, tracking per-employee metadata for salary generation
  emp_attrs_all = []
  emp_meta      = {} # employee_number => { currency:, hire_date:, level: }

  (TARGET_EMPLOYEES - Employee.count).times do |i|
    country   = SEED_COUNTRIES.sample
    currency  = country[:currency]
    level     = LEVELS.sample
    title     = TITLES.sample
    hire_date = Date.new(2015, 1, 1) + rand(0..3650)
    first     = FIRST_NAMES.sample
    last      = LAST_NAMES.sample
    num_str   = format('EMP%06d', next_num + i)

    emp_attrs_all << {
      employee_number: num_str,
      first_name: first,
      last_name: last,
      email: "#{first.downcase}.#{last.downcase}.#{next_num + i}@acme-corp.example",
      country_code: country[:code],
      department_id: dept_ids.sample,
      job_title: title,
      job_level: level,
      hire_date: hire_date,
      status: STATUSES.sample,
      created_at: now,
      updated_at: now
    }

    emp_meta[num_str] = { currency: currency, hire_date: hire_date, level: level }
  end

  # Insert employees in batches, collecting id↔employee_number mappings
  id_by_number = {}
  emp_attrs_all.each_slice(SEED_BATCH) do |batch|
    result = Employee.insert_all!(batch, returning: %w[id employee_number])
    result.each { |row| id_by_number[row['employee_number']] = row['id'] }
    Rails.logger.debug '.'
  end
  Rails.logger.debug { " #{Employee.count} employees total." }

  # Build and insert salary rows
  Rails.logger.debug 'Seed: generating salaries'
  salary_rows = []

  id_by_number.each do |num, emp_id|
    meta      = emp_meta[num]
    currency  = meta[:currency]
    level     = meta[:level]
    hire_date = meta[:hire_date]
    scale     = SUBUNIT.fetch(currency) { raise "add #{currency} to SUBUNIT in seeds.rb" }
    ranges    = SALARY_RANGES[currency] || SALARY_RANGES['USD']
    range     = ranges[level] || ranges['L3']

    num_events = rand(8..15)
    base_minor = rand(range[0]..range[1]) * scale
    event_date = hire_date

    num_events.times do |i|
      salary_rows << {
        employee_id: emp_id,
        amount_minor_units: base_minor,
        currency: currency,
        effective_date: event_date,
        reason: i.zero? ? 'new_hire' : RAISE_REASONS.sample,
        created_at: now,
        updated_at: now
      }

      next_date = event_date >> rand(6..18)
      break if next_date >= Time.zone.today

      event_date = next_date
      base_minor = (base_minor * (1 + (rand(2..8) / 100.0))).round
    end
  end

  salary_rows.each_slice(SEED_BATCH) do |batch|
    Salary.insert_all!(batch)
    Rails.logger.debug '.'
  end
  Rails.logger.debug { " #{Salary.count} salaries total." }
end

# rubocop:enable Rails/SkipsModelValidations
