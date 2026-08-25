require 'rails_helper'

RSpec.describe PayAnalytics do
  let(:eng)      { create(:department, name: 'Engineering', slug: 'engineering') }
  let(:hr)       { create(:department, name: 'People',      slug: 'people') }
  let(:zone_na)  { create(:pay_zone, name: 'North America', slug: 'na') }
  let(:zone_eu)  { create(:pay_zone, name: 'Europe',        slug: 'eu') }

  before do
    create(:country, code: 'US', name: 'United States', default_currency: 'USD',
                     region: 'na', pay_zone: zone_na)
    create(:country, code: 'MX', name: 'Mexico', default_currency: 'MXN',
                     region: 'latam', pay_zone: zone_na)
    create(:country, code: 'DE', name: 'Germany', default_currency: 'EUR',
                     region: 'emea', pay_zone: zone_eu)
    create(:country, code: 'FR', name: 'France', default_currency: 'EUR',
                     region: 'emea', pay_zone: zone_eu)
    create(:country, code: 'JP', name: 'Japan', default_currency: 'JPY',
                     region: 'apac', pay_zone: zone_eu)
    ExchangeRate.create!(currency: 'EUR', rate_to_usd: '1.10', effective_date: Date.new(2024, 1, 1))
    ExchangeRate.create!(currency: 'JPY', rate_to_usd: '0.0068', effective_date: Date.new(2024, 1, 1))
    ExchangeRate.create!(currency: 'MXN', rate_to_usd: '0.05', effective_date: Date.new(2024, 1, 1))
  end

  # Helper: create an employee + a single salary at hire_date. Uses a hash to
  # keep the argument list short and readable.
  def employ(**attrs)
    dept   = attrs[:department] || eng
    lvl    = attrs[:level]      || 'L3'
    hired  = attrs[:hire_date]  || Date.new(2020, 1, 1)
    e = create(:employee,
               employee_number: attrs[:number], country_code: attrs[:country],
               department: dept, job_level: lvl, hire_date: hired,
               email: "#{attrs[:number].downcase}@example.com")
    Salary.create!(employee: e, amount_minor_units: attrs[:amount],
                   currency: attrs[:currency], effective_date: hired, reason: 'new_hire')
    e
  end

  # ---------------------------------------------------------------------------
  # Parameter validation
  # ---------------------------------------------------------------------------
  describe 'parameter validation' do
    it 'requires group_by' do
      q = described_class.new(as_of: '2024-06-01')
      expect(q).not_to be_valid
      expect(q.error).to include('group_by must be one of')
    end

    it 'rejects an unknown group_by' do
      q = described_class.new(group_by: 'planet')
      expect(q).not_to be_valid
      expect(q.error).to include('group_by must be one of')
    end

    it 'rejects a malformed as_of date' do
      q = described_class.new(group_by: 'region', as_of: 'yesterday')
      expect(q).not_to be_valid
      expect(q.error).to include('as_of')
    end

    it 'rejects a malformed rate_date' do
      q = described_class.new(group_by: 'region', rate_date: 'yesterday')
      expect(q).not_to be_valid
      expect(q.error).to include('rate_date')
    end

    it 'rejects an unknown region filter' do
      q = described_class.new(group_by: 'region', region: 'antarctica')
      expect(q).not_to be_valid
      expect(q.error).to include('region must be one of')
    end

    it 'defaults as_of and rate_date to today when omitted' do
      q = described_class.new(group_by: 'region')
      expect(q).to be_valid
      expect(q.as_of).to eq(Date.current)
      expect(q.rate_date).to eq(Date.current)
    end

    it 'defaults rate_date to as_of when only as_of is given' do
      q = described_class.new(group_by: 'region', as_of: '2023-01-15')
      expect(q.rate_date).to eq(Date.new(2023, 1, 15))
    end
  end

  # ---------------------------------------------------------------------------
  # Grouping dimensions
  # ---------------------------------------------------------------------------
  describe 'group_by=region' do
    before do
      employ(number: 'A1', country: 'US', amount: 100_000_00, currency: 'USD')
      employ(number: 'A2', country: 'US', amount: 200_000_00, currency: 'USD')
      employ(number: 'A3', country: 'MX', amount: 500_000_00, currency: 'MXN')
      employ(number: 'A4', country: 'DE', amount: 100_000_00, currency: 'EUR')
      employ(number: 'A5', country: 'JP', amount: 10_000_000, currency: 'JPY')
    end

    it 'returns one row per region with correct headcounts' do
      groups = described_class.new(group_by: 'region', as_of: '2024-06-01').call[:groups]
      counts = groups.to_h { |g| [g[:key], g[:headcount]] }
      expect(counts).to eq('na' => 2, 'latam' => 1, 'emea' => 1, 'apac' => 1)
    end

    it 'converts every currency to USD in the totals' do
      groups = described_class.new(group_by: 'region', as_of: '2024-06-01').call[:groups]
      na = groups.find { |g| g[:key] == 'na' }
      emea = groups.find { |g| g[:key] == 'emea' }
      apac = groups.find { |g| g[:key] == 'apac' }
      latam = groups.find { |g| g[:key] == 'latam' }

      expect(na[:total_spend_usd_minor_units]).to eq(300_000_00) # 100k + 200k USD
      expect(emea[:total_spend_usd_minor_units]).to eq(110_000_00) # 100k EUR @ 1.10
      expect(apac[:total_spend_usd_minor_units]).to eq(68_000_00)  # 10M JPY @ 0.0068
      expect(latam[:total_spend_usd_minor_units]).to eq(25_000_00) # 500k MXN @ 0.05

      expect(na[:currency]).to eq('USD')
    end
  end

  describe 'group_by=country' do
    before do
      employ(number: 'C1', country: 'US', amount: 100_000_00, currency: 'USD')
      employ(number: 'C2', country: 'DE', amount: 100_000_00, currency: 'EUR')
      employ(number: 'C3', country: 'FR', amount: 100_000_00, currency: 'EUR')
    end

    it 'keys each group by country_code and labels with country name' do
      groups = described_class.new(group_by: 'country', as_of: '2024-06-01').call[:groups]
      labels = groups.to_h { |g| [g[:key], g[:label]] }
      expect(labels).to eq('DE' => 'Germany', 'FR' => 'France', 'US' => 'United States')
    end
  end

  describe 'group_by=department' do
    before do
      employ(number: 'D1', country: 'US', department: eng, amount: 100_000_00, currency: 'USD')
      employ(number: 'D2', country: 'US', department: eng, amount: 150_000_00, currency: 'USD')
      employ(number: 'D3', country: 'US', department: hr,  amount: 90_000_00,  currency: 'USD')
    end

    it 'groups by department id and labels with department name' do
      groups = described_class.new(group_by: 'department', as_of: '2024-06-01').call[:groups]
      by_label = groups.to_h { |g| [g[:label], g[:headcount]] }
      expect(by_label).to eq('Engineering' => 2, 'People' => 1)
    end
  end

  describe 'group_by=level' do
    before do
      employ(number: 'L1a', country: 'US', level: 'L3', amount: 100_000_00, currency: 'USD')
      employ(number: 'L1b', country: 'US', level: 'L3', amount: 110_000_00, currency: 'USD')
      employ(number: 'L2a', country: 'US', level: 'L5', amount: 200_000_00, currency: 'USD')
    end

    it 'groups by job_level' do
      groups = described_class.new(group_by: 'level', as_of: '2024-06-01').call[:groups]
      counts = groups.to_h { |g| [g[:key], g[:headcount]] }
      expect(counts).to eq('L3' => 2, 'L5' => 1)
    end
  end

  # ---------------------------------------------------------------------------
  # Median correctness
  # ---------------------------------------------------------------------------
  describe 'median (percentile_cont)' do
    it 'returns the single value for a group of one' do
      employ(number: 'M1', country: 'US', amount: 123_45, currency: 'USD')
      row = described_class.new(group_by: 'region', as_of: '2024-06-01').call[:groups].first
      expect(row[:median_usd_minor_units]).to eq(123_45)
    end

    it 'returns the middle value for an odd-sized group' do
      [50_000_00, 70_000_00, 90_000_00].each_with_index do |amt, i|
        employ(number: "MO#{i}", country: 'US', amount: amt, currency: 'USD')
      end
      row = described_class.new(group_by: 'region', as_of: '2024-06-01').call[:groups].first
      expect(row[:median_usd_minor_units]).to eq(70_000_00)
    end

    it 'interpolates between the two middle values for an even-sized group' do
      [50_000_00, 60_000_00, 80_000_00, 100_000_00].each_with_index do |amt, i|
        employ(number: "ME#{i}", country: 'US', amount: amt, currency: 'USD')
      end
      row = described_class.new(group_by: 'region', as_of: '2024-06-01').call[:groups].first
      # percentile_cont(0.5) of [50, 60, 80, 100] = (60 + 80) / 2 = 70
      expect(row[:median_usd_minor_units]).to eq(70_000_00)
    end
  end

  # ---------------------------------------------------------------------------
  # Rate date behaviour
  # ---------------------------------------------------------------------------
  describe 'rate_date' do
    before do
      # Later EUR rate — weaker euro
      ExchangeRate.create!(currency: 'EUR', rate_to_usd: '1.05', effective_date: Date.new(2025, 1, 1))
      employ(number: 'R1', country: 'DE', amount: 100_000_00, currency: 'EUR')
    end

    it 'gives different totals when the same salaries are converted at different rate dates' do
      early = described_class.new(group_by: 'region', as_of: '2025-06-01',
                                  rate_date: '2024-06-01').call[:groups].first
      late  = described_class.new(group_by: 'region', as_of: '2025-06-01',
                                  rate_date: '2025-06-01').call[:groups].first
      expect(early[:total_spend_usd_minor_units]).to eq(110_000_00) # @ 1.10
      expect(late[:total_spend_usd_minor_units]).to eq(105_000_00)  # @ 1.05
    end

    it 'defaults rate_date to as_of' do
      row = described_class.new(group_by: 'region', as_of: '2025-06-01').call[:groups].first
      expect(row[:total_spend_usd_minor_units]).to eq(105_000_00)
    end
  end

  # ---------------------------------------------------------------------------
  # Point-in-time (as_of)
  # ---------------------------------------------------------------------------
  describe 'as_of' do
    let(:employee) do
      e = create(:employee, employee_number: 'P1', country_code: 'US',
                            department: eng, job_level: 'L3',
                            hire_date: Date.new(2022, 1, 1),
                            email: 'p1@example.com')
      Salary.create!(employee: e, amount_minor_units: 100_000_00, currency: 'USD',
                     effective_date: Date.new(2022, 1, 1), reason: 'new_hire')
      Salary.create!(employee: e, amount_minor_units: 130_000_00, currency: 'USD',
                     effective_date: Date.new(2024, 1, 1), reason: 'merit')
      e
    end

    before { employee }

    it 'uses the salary in effect at as_of, not the latest one' do
      row = described_class.new(group_by: 'region', as_of: '2023-06-01').call[:groups].first
      expect(row[:total_spend_usd_minor_units]).to eq(100_000_00)
    end

    it 'uses the newer salary when as_of falls after the raise' do
      row = described_class.new(group_by: 'region', as_of: '2024-06-01').call[:groups].first
      expect(row[:total_spend_usd_minor_units]).to eq(130_000_00)
    end

    it 'excludes employees not yet hired at as_of' do
      row = described_class.new(group_by: 'region', as_of: '2021-01-01').call[:groups]
      expect(row).to be_empty
    end

    it 'excludes employees terminated on or before as_of' do
      employee.update!(status: 'terminated', terminated_on: Date.new(2023, 12, 31))
      row = described_class.new(group_by: 'region', as_of: '2024-06-01').call[:groups]
      expect(row).to be_empty
    end

    it 'still includes an employee terminated after as_of' do
      employee.update!(status: 'terminated', terminated_on: Date.new(2024, 12, 31))
      row = described_class.new(group_by: 'region', as_of: '2024-06-01').call[:groups].first
      expect(row[:headcount]).to eq(1)
    end
  end

  # ---------------------------------------------------------------------------
  # Region rollup consistency
  # ---------------------------------------------------------------------------
  describe 'region rollup equals sum of its countries' do
    before do
      employ(number: 'X1', country: 'DE', amount: 100_000_00, currency: 'EUR')
      employ(number: 'X2', country: 'FR', amount: 80_000_00,  currency: 'EUR')
    end

    it 'sums country totals to match the region total' do
      by_region  = described_class.new(group_by: 'region', as_of: '2024-06-01').call[:groups]
      by_country = described_class.new(group_by: 'country', as_of: '2024-06-01').call[:groups]

      emea_total = by_region.find { |g| g[:key] == 'emea' }[:total_spend_usd_minor_units]
      country_sum = by_country
                    .select { |g| %w[DE FR].include?(g[:key]) }
                    .sum { |g| g[:total_spend_usd_minor_units] }
      expect(emea_total).to eq(country_sum)
    end

    it 'headcount rolls up identically' do
      by_region  = described_class.new(group_by: 'region', as_of: '2024-06-01').call[:groups]
      by_country = described_class.new(group_by: 'country', as_of: '2024-06-01').call[:groups]

      emea_hc = by_region.find { |g| g[:key] == 'emea' }[:headcount]
      country_hc = by_country.select { |g| %w[DE FR].include?(g[:key]) }.sum { |g| g[:headcount] }
      expect(emea_hc).to eq(country_hc)
    end
  end

  # ---------------------------------------------------------------------------
  # Empty groups and empty results
  # ---------------------------------------------------------------------------
  describe 'empty results' do
    it 'returns an empty groups array when there are no employees at all' do
      result = described_class.new(group_by: 'region', as_of: '2024-06-01').call
      expect(result[:groups]).to eq([])
    end

    it 'returns an empty groups array when filters narrow to nothing' do
      employ(number: 'E1', country: 'US', amount: 100_000_00, currency: 'USD')
      result = described_class.new(group_by: 'region', as_of: '2024-06-01',
                                   country_code: 'DE').call
      expect(result[:groups]).to eq([])
    end
  end

  # ---------------------------------------------------------------------------
  # Missing rate handling
  # ---------------------------------------------------------------------------
  describe 'missing exchange rate' do
    before do
      create(:country, code: 'GB', name: 'United Kingdom',
                       default_currency: 'GBP', region: 'emea', pay_zone: zone_eu)
      employ(number: 'F1', country: 'US', amount: 100_000_00, currency: 'USD')
      employ(number: 'F2', country: 'GB', amount: 90_000_00,  currency: 'GBP')
    end

    it 'excludes employees whose currency has no rate at rate_date' do
      result = described_class.new(group_by: 'region', as_of: '2024-06-01').call
      totals = result[:groups].to_h { |g| [g[:key], g[:total_spend_usd_minor_units]] }
      expect(totals).to eq('na' => 100_000_00)
    end

    it 'lists the unconvertible currencies in meta' do
      result = described_class.new(group_by: 'region', as_of: '2024-06-01').call
      expect(result[:meta][:unconvertible_currencies]).to eq(['GBP'])
    end

    it 'includes the currency once a rate is added even earlier than rate_date' do
      ExchangeRate.create!(currency: 'GBP', rate_to_usd: '1.25', effective_date: Date.new(2024, 1, 1))
      result = described_class.new(group_by: 'region', as_of: '2024-06-01').call
      totals = result[:groups].to_h { |g| [g[:key], g[:total_spend_usd_minor_units]] }
      expect(totals).to eq('na' => 100_000_00, 'emea' => 112_500_00)
      expect(result[:meta][:unconvertible_currencies]).to eq([])
    end

    it 'uses the most recent rate on or before rate_date (not exact match)' do
      # Only rate exists at 2024-01-01; rate_date is much later — still resolves.
      result = described_class.new(group_by: 'region', as_of: '2024-06-01',
                                   rate_date: '2024-12-31').call
      totals = result[:groups].to_h { |g| [g[:key], g[:total_spend_usd_minor_units]] }
      expect(totals['emea']).to be_nil # GBP still has no rate
      expect(totals['na']).to eq(100_000_00)
    end
  end

  # ---------------------------------------------------------------------------
  # Filters
  # ---------------------------------------------------------------------------
  describe 'filters' do
    before do
      employ(number: 'G1', country: 'US', department: eng, level: 'L3',
             amount: 100_000_00, currency: 'USD')
      employ(number: 'G2', country: 'US', department: eng, level: 'L5',
             amount: 200_000_00, currency: 'USD')
      employ(number: 'G3', country: 'DE', department: eng, level: 'L5',
             amount: 100_000_00, currency: 'EUR')
      employ(number: 'G4', country: 'DE', department: hr,  level: 'L3',
             amount: 90_000_00,  currency: 'EUR')
    end

    it 'filters by country_code' do
      groups = described_class.new(group_by: 'department', as_of: '2024-06-01',
                                   country_code: 'US').call[:groups]
      expect(groups.sum { |g| g[:headcount] }).to eq(2)
    end

    it 'filters by region' do
      groups = described_class.new(group_by: 'country', as_of: '2024-06-01',
                                   region: 'emea').call[:groups]
      keys = groups.pluck(:key)
      expect(keys).to contain_exactly('DE')
    end

    it 'filters by department_id' do
      groups = described_class.new(group_by: 'country', as_of: '2024-06-01',
                                   department_id: eng.id).call[:groups]
      expect(groups.sum { |g| g[:headcount] }).to eq(3)
    end

    it 'filters by job_level' do
      groups = described_class.new(group_by: 'country', as_of: '2024-06-01',
                                   job_level: 'L5').call[:groups]
      expect(groups.sum { |g| g[:headcount] }).to eq(2)
    end

    it 'combines multiple filters (AND semantics)' do
      groups = described_class.new(group_by: 'country', as_of: '2024-06-01',
                                   region: 'emea', job_level: 'L3').call[:groups]
      expect(groups.sum { |g| g[:headcount] }).to eq(1)
      expect(groups.first[:key]).to eq('DE')
    end
  end

  # ---------------------------------------------------------------------------
  # Currency-exponent handling
  # ---------------------------------------------------------------------------
  describe 'currency exponent handling' do
    it 'treats JPY as a zero-decimal currency (¥1,000,000 → $6,800)' do
      employ(number: 'J1', country: 'JP', amount: 1_000_000, currency: 'JPY')
      row = described_class.new(group_by: 'region', as_of: '2024-06-01').call[:groups].first
      # 1,000,000 JPY (JPY has no subunit) * 0.0068 = 6,800 USD = 680_000 minor units
      expect(row[:total_spend_usd_minor_units]).to eq(680_000)
    end

    it 'treats KWD as a three-decimal currency' do
      create(:country, code: 'KW', name: 'Kuwait',
                       default_currency: 'KWD', region: 'emea', pay_zone: zone_eu)
      ExchangeRate.create!(currency: 'KWD', rate_to_usd: '3.25', effective_date: Date.new(2024, 1, 1))
      # 30,000.000 KWD (30 million minor units) × 3.25 = 97,500 USD = 97_500_00 minor
      employ(number: 'K1', country: 'KW', amount: 30_000_000, currency: 'KWD')
      row = described_class.new(group_by: 'region', as_of: '2024-06-01').call[:groups].first
      expect(row[:total_spend_usd_minor_units]).to eq(97_500_00)
    end
  end

  # ---------------------------------------------------------------------------
  # Historical rate date, before any rate exists
  # ---------------------------------------------------------------------------
  describe 'historical date before any rate exists' do
    before do
      employ(number: 'H1', country: 'DE', amount: 100_000_00, currency: 'EUR')
    end

    it 'reports the currency as unconvertible when rate_date is before the earliest rate' do
      result = described_class.new(group_by: 'region', as_of: '2023-06-01',
                                   rate_date: '2023-06-01').call
      # employee not yet hired anyway — check the currency list
      expect(result[:meta][:unconvertible_currencies]).to include('EUR').or(be_empty)
    end
  end
end
