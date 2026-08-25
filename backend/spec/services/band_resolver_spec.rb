require 'rails_helper'

RSpec.describe BandResolver do
  let(:zone)    { create(:pay_zone, name: 'North America', slug: 'na') }
  let(:dept)    { create(:department) }
  let(:country) { create(:country, code: 'US', name: 'United States', default_currency: 'USD', region: 'na', pay_zone: zone) }

  let(:employee) do
    create(:employee, country_code: country.code, department: dept,
                      job_title: 'Engineer', job_level: 'L3',
                      hire_date: Date.new(2020, 1, 1))
  end

  let(:on_date)   { Date.new(2024, 6, 1) }
  let(:rate_date) { on_date }

  before do
    ExchangeRate.create!(currency: 'EUR', rate_to_usd: '1.10', effective_date: Date.new(2024, 1, 1))
    ExchangeRate.create!(currency: 'JPY', rate_to_usd: '0.0068', effective_date: Date.new(2024, 1, 1))
  end

  def give_salary(amount:, currency: 'USD', date: Date.new(2020, 1, 1))
    Salary.create!(employee:, amount_minor_units: amount, currency:,
                   effective_date: date, reason: 'new_hire')
  end

  def make_band(min:, mid:, max:, currency: 'USD',
                from: Date.new(2020, 1, 1), to: nil,
                title: 'Engineer', level: 'L3')
    create(:salary_band, pay_zone: zone, job_title: title, job_level: level,
           currency:, min_minor_units: min, mid_minor_units: mid, max_minor_units: max,
           effective_from: from, effective_to: to)
  end

  # ---------------------------------------------------------------------------
  # Argument guards
  # ---------------------------------------------------------------------------
  it 'raises ArgumentError for nil employee' do
    expect { described_class.resolve(employee: nil, on_date: Date.current) }
      .to raise_error(ArgumentError, /employee/)
  end

  it 'raises ArgumentError for nil on_date' do
    expect { described_class.resolve(employee:, on_date: nil) }
      .to raise_error(ArgumentError, /on_date/)
  end

  # ---------------------------------------------------------------------------
  # :no_salary
  # ---------------------------------------------------------------------------
  describe ':no_salary' do
    it 'returns no_salary when the employee has no salary record on that date' do
      result = described_class.resolve(employee:, on_date:)
      expect(result.reason).to eq(:no_salary)
      expect(result.compa_ratio).to be_nil
    end
  end

  # ---------------------------------------------------------------------------
  # :unzoned_country
  # ---------------------------------------------------------------------------
  describe ':unzoned_country' do
    let(:unzoned_country) { create(:country, code: 'XZ', name: 'Unzoned', default_currency: 'USD', region: 'na', pay_zone: nil) }
    let(:unzoned_emp) do
      create(:employee, country_code: unzoned_country.code, department: dept,
                        job_title: 'Engineer', job_level: 'L3',
                        hire_date: Date.new(2020, 1, 1))
    end

    before do
      Salary.create!(employee: unzoned_emp, amount_minor_units: 100_000_00,
                     currency: 'USD', effective_date: Date.new(2020, 1, 1), reason: 'new_hire')
      make_band(min: 80_000_00, mid: 100_000_00, max: 130_000_00)
    end

    it 'returns :unzoned_country' do
      result = described_class.resolve(employee: unzoned_emp, on_date:)
      expect(result.reason).to eq(:unzoned_country)
    end
  end

  # ---------------------------------------------------------------------------
  # :no_band
  # ---------------------------------------------------------------------------
  describe ':no_band' do
    before { give_salary(amount: 100_000_00) }

    it 'returns :no_band when no band covers the employee title/level in the zone' do
      result = described_class.resolve(employee:, on_date:)
      expect(result.reason).to eq(:no_band)
    end
  end

  # ---------------------------------------------------------------------------
  # :no_rate — salary currency has no rate
  # ---------------------------------------------------------------------------
  describe ':no_rate (salary currency)' do
    before do
      give_salary(amount: 1_000_000, currency: 'JPY')
      make_band(min: 5_000_00, mid: 7_000_00, max: 9_000_00, currency: 'USD')
    end

    it 'returns :no_rate when the salary currency has no rate at rate_date' do
      result = described_class.resolve(employee:, on_date:, rate_date: Date.new(2020, 1, 1))
      expect(result.reason).to eq(:no_rate)
    end
  end

  # ---------------------------------------------------------------------------
  # :no_rate — band currency has no rate
  # ---------------------------------------------------------------------------
  describe ':no_rate (band currency)' do
    before do
      give_salary(amount: 100_000_00, currency: 'USD')
      make_band(min: 80_000_00, mid: 100_000_00, max: 130_000_00, currency: 'EUR')
    end

    it 'returns :no_rate when the band currency has no rate at rate_date' do
      result = described_class.resolve(employee:, on_date:, rate_date: Date.new(2020, 1, 1))
      expect(result.reason).to eq(:no_rate)
    end
  end

  # ---------------------------------------------------------------------------
  # :ok — happy path
  # ---------------------------------------------------------------------------
  describe ':ok result' do
    before do
      give_salary(amount: 100_000_00)
      make_band(min: 80_000_00, mid: 100_000_00, max: 130_000_00)
    end

    let(:result) { described_class.resolve(employee:, on_date:) }

    it 'returns :ok' do
      expect(result.reason).to eq(:ok)
    end

    it 'returns the matching band' do
      expect(result.band).to be_a(SalaryBand)
    end

    it 'returns the salary in USD minor units' do
      expect(result.salary_usd_minor_units).to eq(100_000_00)
    end

    it 'returns band min/mid/max in USD minor units' do
      expect(result.band_min_usd_minor_units).to eq(80_000_00)
      expect(result.band_mid_usd_minor_units).to eq(100_000_00)
      expect(result.band_max_usd_minor_units).to eq(130_000_00)
    end
  end

  # ---------------------------------------------------------------------------
  # Bucket boundary values (Key test)
  # ---------------------------------------------------------------------------
  describe 'bucket boundary values' do
    before do
      make_band(min: 80_000_00, mid: 100_000_00, max: 130_000_00)
    end

    it 'salary exactly at min → :within' do
      give_salary(amount: 80_000_00)
      expect(described_class.resolve(employee:, on_date:).bucket).to eq(:within)
    end

    it 'salary exactly at max → :within' do
      give_salary(amount: 130_000_00)
      expect(described_class.resolve(employee:, on_date:).bucket).to eq(:within)
    end

    it 'salary at max + 1 minor unit → :above' do
      give_salary(amount: 130_000_01)
      expect(described_class.resolve(employee:, on_date:).bucket).to eq(:above)
    end

    it 'salary at min - 1 minor unit → :below' do
      give_salary(amount: 79_999_99)
      expect(described_class.resolve(employee:, on_date:).bucket).to eq(:below)
    end

    it 'salary exactly at mid → compa_ratio = 1.0' do
      give_salary(amount: 100_000_00)
      result = described_class.resolve(employee:, on_date:)
      expect(result.compa_ratio).to eq(BigDecimal('1.0'))
    end
  end

  # ---------------------------------------------------------------------------
  # Band currency ≠ salary currency (Key test)
  # ---------------------------------------------------------------------------
  describe 'band currency differs from salary currency' do
    before do
      # Salary in EUR: 100,000 EUR at 1.10 = 110,000 USD
      give_salary(amount: 100_000_00, currency: 'EUR')
      # Band in USD: mid = 110,000 USD → compa-ratio should be exactly 1.0
      make_band(min: 88_000_00, mid: 110_000_00, max: 143_000_00, currency: 'USD')
    end

    it 'normalizes both to USD at the same rate_date' do
      result = described_class.resolve(employee:, on_date:)
      expect(result.reason).to eq(:ok)
      expect(result.salary_usd_minor_units).to eq(110_000_00)
      expect(result.band_mid_usd_minor_units).to eq(110_000_00)
      expect(result.compa_ratio).to eq(BigDecimal('1.0'))
    end
  end

  # ---------------------------------------------------------------------------
  # Band changed mid-period (Key test)
  # ---------------------------------------------------------------------------
  describe 'band changed mid-period' do
    before do
      give_salary(amount: 100_000_00)
      # Old band: Jan 2024 – Jan 2025; mid = 90k
      make_band(min: 75_000_00, mid: 90_000_00, max: 120_000_00,
                from: Date.new(2024, 1, 1), to: Date.new(2025, 1, 1))
      # New band: Jan 2025 onward; mid = 110k
      make_band(min: 85_000_00, mid: 110_000_00, max: 145_000_00,
                from: Date.new(2025, 1, 1), to: nil)
    end

    it 'picks the old band for a date in its window' do
      result = described_class.resolve(employee:, on_date: Date.new(2024, 6, 1))
      expect(result.band_mid_usd_minor_units).to eq(90_000_00)
    end

    it 'picks the new band for a date in its window' do
      give_salary(amount: 100_000_00, date: Date.new(2025, 1, 1))
      result = described_class.resolve(employee:, on_date: Date.new(2025, 6, 1))
      expect(result.band_mid_usd_minor_units).to eq(110_000_00)
    end
  end

  # ---------------------------------------------------------------------------
  # JPY (zero-decimal) and band in JPY
  # ---------------------------------------------------------------------------
  describe 'JPY zero-decimal currency' do
    let(:jp_country) { create(:country, code: 'JP', name: 'Japan', default_currency: 'JPY', region: 'apac', pay_zone: zone) }
    let(:jp_emp) do
      create(:employee, country_code: jp_country.code, department: dept,
                        job_title: 'Engineer', job_level: 'L3',
                        hire_date: Date.new(2020, 1, 1))
    end

    before do
      Salary.create!(employee: jp_emp, amount_minor_units: 10_000_000,
                     currency: 'JPY', effective_date: Date.new(2020, 1, 1), reason: 'new_hire')
      # 10,000,000 JPY minor units * 0.0068 * 100 = 6,800,000 USD minor units
      # Band mid = 10,000,000 JPY → same USD amount → compa-ratio 1.0
      make_band(min: 8_000_000, mid: 10_000_000, max: 12_000_000, currency: 'JPY')
    end

    it 'converts JPY correctly and produces compa_ratio = 1.0 at mid' do
      result = described_class.resolve(employee: jp_emp, on_date:)
      expect(result.reason).to eq(:ok)
      # 10M JPY (minor units, exponent 0) * 0.0068 * 100 (USD subunit) = 6,800,000
      expect(result.salary_usd_minor_units).to eq(6_800_000)
      expect(result.compa_ratio).to eq(BigDecimal('1.0'))
    end
  end
end
