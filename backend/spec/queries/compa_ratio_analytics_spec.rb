require 'rails_helper'

RSpec.describe CompaRatioAnalytics do
  let(:zone_na)   { create(:pay_zone, name: 'North America', slug: 'na-cr') }
  let(:zone_emea) { create(:pay_zone, name: 'Europe', slug: 'emea-cr') }
  let(:dept)      { create(:department, name: 'Engineering', slug: 'eng-cr') }
  let(:as_of)     { '2024-06-01' }
  let(:rate_date) { '2024-06-01' }

  before do
    create(:country, code: 'US', name: 'United States', default_currency: 'USD',
                     region: 'na', pay_zone: zone_na)
    create(:country, code: 'DE', name: 'Germany', default_currency: 'EUR',
                     region: 'emea', pay_zone: zone_emea)
    ExchangeRate.create!(currency: 'EUR', rate_to_usd: '1.10', effective_date: Date.new(2024, 1, 1))
  end

  # rubocop:disable Metrics/ParameterLists
  def employ(number:, country:, amount:, currency: 'USD', level: 'L3',
             title: 'Engineer', hired: Date.new(2020, 1, 1))
    e = create(:employee, employee_number: number, country_code: country,
                          department: dept, job_title: title, job_level: level, hire_date: hired,
                          email: "#{number.downcase}@example.com")
    Salary.create!(employee: e, amount_minor_units: amount, currency:,
                   effective_date: hired, reason: 'new_hire')
    e
  end
  # rubocop:enable Metrics/ParameterLists

  # rubocop:disable Metrics/ParameterLists
  def make_band(zone:, min:, mid:, max:, title: 'Engineer', level: 'L3',
                currency: 'USD', from: Date.new(2020, 1, 1), to: nil)
    create(:salary_band, pay_zone: zone, job_title: title, job_level: level,
                         min_minor_units: min, mid_minor_units: mid, max_minor_units: max,
                         currency:, effective_from: from, effective_to: to)
  end
  # rubocop:enable Metrics/ParameterLists

  # ---------------------------------------------------------------------------
  # Parameter validation (mirrors PayAnalytics)
  # ---------------------------------------------------------------------------
  describe 'parameter validation' do
    it 'requires group_by' do
      q = described_class.new(as_of:)
      expect(q).not_to be_valid
      expect(q.error).to include('group_by must be one of')
    end

    it 'rejects an unknown group_by' do
      q = described_class.new(group_by: 'planet')
      expect(q).not_to be_valid
    end

    it 'rejects malformed as_of' do
      q = described_class.new(group_by: 'region', as_of: 'yesterday')
      expect(q).not_to be_valid
      expect(q.error).to include('as_of')
    end

    it 'rejects malformed rate_date' do
      q = described_class.new(group_by: 'region', rate_date: 'yesterday')
      expect(q).not_to be_valid
      expect(q.error).to include('rate_date')
    end

    it 'rejects an unknown region filter' do
      q = described_class.new(group_by: 'region', region: 'antarctica')
      expect(q).not_to be_valid
    end
  end

  # ---------------------------------------------------------------------------
  # Basic headcount and coverage (no band → unresolved)
  # ---------------------------------------------------------------------------
  describe 'no matching band → unresolved' do
    before { employ(number: 'CR1', country: 'US', amount: 100_000_00) }

    it 'counts employee in headcount but not covered_headcount' do
      groups = described_class.new(group_by: 'region', as_of:).call[:groups]
      na = groups.find { |g| g[:key] == 'na' }
      expect(na[:headcount]).to eq(1)
      expect(na[:covered_headcount]).to eq(0)
      expect(na[:unresolved]).to eq(1)
      expect(na[:avg_compa_ratio]).to be_nil
    end
  end

  # ---------------------------------------------------------------------------
  # Covered employees and correct bucket classification
  # ---------------------------------------------------------------------------
  describe 'covered employees' do
    before do
      make_band(zone: zone_na, min: 80_000_00, mid: 100_000_00, max: 130_000_00)
      employ(number: 'CR2', country: 'US', amount: 80_000_00)   # at min → within
      employ(number: 'CR3', country: 'US', amount: 60_000_00)   # below min → below
      employ(number: 'CR4', country: 'US', amount: 150_000_00)  # above max → above
    end

    let(:na) do
      described_class.new(group_by: 'region', as_of:, rate_date:).call[:groups]
                     .find { |g| g[:key] == 'na' }
    end

    it 'counts all three employees in headcount' do
      expect(na[:headcount]).to eq(3)
    end

    it 'counts all three as covered' do
      expect(na[:covered_headcount]).to eq(3)
    end

    it 'buckets correctly: 1 within, 1 below, 1 above' do
      expect(na[:within]).to eq(1)
      expect(na[:below]).to eq(1)
      expect(na[:above]).to eq(1)
      expect(na[:unresolved]).to eq(0)
    end

    it 'returns avg_compa_ratio as a 4dp string' do
      # Salaries: 80k, 60k, 150k USD; midpoint 100k → ratios: 0.8, 0.6, 1.5
      ratio = na[:avg_compa_ratio].to_f
      expect(ratio).to be_within(0.0001).of((0.8 + 0.6 + 1.5) / 3.0)
      expect(na[:avg_compa_ratio]).to match(/\A\d+\.\d{4}\z/)
    end
  end

  # ---------------------------------------------------------------------------
  # Band currency ≠ salary currency — both normalized to USD
  # ---------------------------------------------------------------------------
  describe 'band currency differs from salary currency' do
    before do
      # EUR salary: 100,000 EUR → 110,000 USD; band mid = 110,000 USD → ratio 1.0
      make_band(zone: zone_emea, min: 88_000_00, mid: 110_000_00, max: 143_000_00,
                currency: 'USD')
      employ(number: 'CR5', country: 'DE', amount: 100_000_00, currency: 'EUR')
    end

    it 'resolves compa-ratio correctly across currencies' do
      groups = described_class.new(group_by: 'region', as_of:, rate_date:).call[:groups]
      emea = groups.find { |g| g[:key] == 'emea' }
      expect(emea[:covered_headcount]).to eq(1)
      expect(emea[:avg_compa_ratio].to_f).to be_within(0.0001).of(1.0)
    end
  end

  # ---------------------------------------------------------------------------
  # Missing exchange rate → employee excluded from aggregate
  # ---------------------------------------------------------------------------
  describe 'salary currency has no rate' do
    before do
      create(:country, code: 'GB', name: 'UK', default_currency: 'GBP',
                       region: 'emea', pay_zone: zone_emea)
      employ(number: 'CR6', country: 'US', amount: 100_000_00) # USD, has rate
      employ(number: 'CR7', country: 'GB', amount: 90_000_00, currency: 'GBP') # no GBP rate
      make_band(zone: zone_na, min: 80_000_00, mid: 100_000_00, max: 130_000_00)
    end

    it 'excludes the unconvertible employee from all group rows' do
      result = described_class.new(group_by: 'region', as_of:).call
      groups = result[:groups]
      # GBP employee excluded → emea row should be absent or have 0 headcount
      emea = groups.find { |g| g[:key] == 'emea' }
      expect(emea).to be_nil
    end

    it 'lists GBP in unconvertible_currencies in meta' do
      result = described_class.new(group_by: 'region', as_of:).call
      expect(result[:meta][:unconvertible_currencies]).to include('GBP')
    end
  end

  # ---------------------------------------------------------------------------
  # Region rollup invariant (headcount mirrors PayAnalytics)
  # ---------------------------------------------------------------------------
  describe 'region rollup equals sum of its countries' do
    before do
      make_band(zone: zone_na, min: 80_000_00, mid: 100_000_00, max: 130_000_00)
      employ(number: 'R1', country: 'US', amount: 100_000_00)
      employ(number: 'R2', country: 'US', amount: 120_000_00)
    end

    it 'headcount by region matches headcount by country for the same population' do
      by_region  = described_class.new(group_by: 'region', as_of:).call[:groups]
      by_country = described_class.new(group_by: 'country', as_of:).call[:groups]

      na_hc  = by_region.find  { |g| g[:key] == 'na' }[:headcount]
      us_hc  = by_country.find { |g| g[:key] == 'US' }[:headcount]
      expect(na_hc).to eq(us_hc)
    end
  end

  # ---------------------------------------------------------------------------
  # meta: uncovered_combinations count
  # ---------------------------------------------------------------------------
  describe 'meta.uncovered_combinations' do
    before do
      # One employee with a band (covered)
      make_band(zone: zone_na, min: 80_000_00, mid: 100_000_00, max: 130_000_00)
      employ(number: 'UC1', country: 'US', amount: 100_000_00)
      # One employee without a band (uncovered)
      employ(number: 'UC2', country: 'US', amount: 100_000_00, title: 'Designer', level: 'L4')
    end

    it 'counts uncovered (zone, title, level) combinations' do
      result = described_class.new(group_by: 'region', as_of:).call
      expect(result[:meta][:uncovered_combinations].to_i).to eq(1)
    end
  end

  # ---------------------------------------------------------------------------
  # Empty result
  # ---------------------------------------------------------------------------
  it 'returns empty groups when no employees exist' do
    result = described_class.new(group_by: 'region', as_of:).call
    expect(result[:groups]).to eq([])
  end
end
