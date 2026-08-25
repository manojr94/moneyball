require 'rails_helper'

RSpec.describe SalaryBand do
  let(:zone) { create(:pay_zone) }

  def valid_attrs(overrides = {})
    { pay_zone: zone, job_title: 'Engineer', job_level: 'L3', currency: 'USD',
      min_minor_units: 80_000_00, mid_minor_units: 100_000_00, max_minor_units: 130_000_00,
      effective_from: 2.years.ago.to_date }.merge(overrides)
  end

  # ---------------------------------------------------------------------------
  # Validations
  # ---------------------------------------------------------------------------
  describe 'validations' do
    it 'saves with valid attributes' do
      expect(described_class.create(valid_attrs)).to be_persisted
    end

    it 'requires job_title' do
      expect(described_class.new(valid_attrs(job_title: nil))).not_to be_valid
    end

    it 'requires job_level' do
      expect(described_class.new(valid_attrs(job_level: nil))).not_to be_valid
    end

    it 'requires effective_from' do
      expect(described_class.new(valid_attrs(effective_from: nil))).not_to be_valid
    end

    it 'requires currency in A-Z{3} format' do
      expect(described_class.new(valid_attrs(currency: 'usd'))).not_to be_valid
      expect(described_class.new(valid_attrs(currency: 'USDX'))).not_to be_valid
    end

    it 'rejects an unknown ISO 4217 code' do
      band = described_class.new(valid_attrs(currency: 'XYZ'))
      expect(band).not_to be_valid
      expect(band.errors[:currency].join).to include('recognised')
    end

    it 'rejects effective_to <= effective_from' do
      band = described_class.new(valid_attrs(effective_to: 3.years.ago.to_date))
      expect(band).not_to be_valid
    end

    it 'accepts effective_to nil (open-ended)' do
      expect(described_class.new(valid_attrs(effective_to: nil))).to be_valid
    end

    it 'rejects max < min' do
      band = described_class.new(valid_attrs(min_minor_units: 100_000_00,
                                             mid_minor_units: 90_000_00,
                                             max_minor_units: 70_000_00))
      expect(band).not_to be_valid
      expect(band.errors[:base].join).to include('min must be <= mid')
    end

    it 'rejects mid < min (even when max >= mid)' do
      band = described_class.new(valid_attrs(min_minor_units: 100_000_00,
                                             mid_minor_units: 80_000_00,
                                             max_minor_units: 130_000_00))
      expect(band).not_to be_valid
    end

    it 'accepts equal min/mid/max (degenerate band)' do
      expect(described_class.new(valid_attrs(min_minor_units: 100_000_00,
                                             mid_minor_units: 100_000_00,
                                             max_minor_units: 100_000_00))).to be_valid
    end
  end

  # ---------------------------------------------------------------------------
  # Immutability guard
  # ---------------------------------------------------------------------------
  describe 'before_update guard' do
    let!(:band) { create(:salary_band, valid_attrs) }

    it 'allows closing (effective_to from nil to a later date)' do
      close_date = effective_from_plus_one_day(band)
      expect { band.update!(effective_to: close_date) }.not_to raise_error
      expect(band.reload.effective_to).to eq(close_date)
    end

    it 'raises when changing min_minor_units' do
      expect { band.update!(min_minor_units: 50_000_00) }
        .to raise_error(ActiveRecord::RecordNotSaved)
    end

    it 'raises when changing job_title' do
      expect { band.update!(job_title: 'Director') }
        .to raise_error(ActiveRecord::RecordNotSaved)
    end

    it 'raises when changing effective_from' do
      expect { band.update!(effective_from: 1.year.ago.to_date) }
        .to raise_error(ActiveRecord::RecordNotSaved)
    end

    it 'raises when attempting to re-set an already-set effective_to' do
      closed = create(:salary_band, :closed, pay_zone: zone)
      expect { closed.update!(effective_to: Date.current + 30) }
        .to raise_error(ActiveRecord::RecordNotSaved)
    end
  end

  # ---------------------------------------------------------------------------
  # scope :covering
  # ---------------------------------------------------------------------------
  describe '.covering' do
    let!(:past_band) do
      create(:salary_band, :closed, pay_zone: zone, job_title: 'Engineer', job_level: 'L3')
    end
    let!(:current_band) do
      create(:salary_band, :current, pay_zone: zone, job_title: 'Engineer', job_level: 'L4')
    end

    it 'returns the open-ended band as of today' do
      expect(described_class.covering(Date.current)).to include(current_band)
    end

    it 'excludes a band whose effective_to is in the past' do
      expect(described_class.covering(Date.current)).not_to include(past_band)
    end

    it 'includes a closed band on a date within its window' do
      date_inside = past_band.effective_from + 1
      expect(described_class.covering(date_inside)).to include(past_band)
    end
  end

  # ---------------------------------------------------------------------------
  # Band changed mid-period
  # ---------------------------------------------------------------------------
  describe 'band changed mid-period' do
    it 'creates two adjacent windows and resolver picks the correct one' do
      old_band = create(:salary_band, pay_zone: zone, job_title: 'Manager', job_level: 'L5',
                        effective_from: Date.new(2024, 1, 1),
                        effective_to:   Date.new(2025, 1, 1),
                        min_minor_units: 80_000_00,
                        mid_minor_units: 100_000_00,
                        max_minor_units: 130_000_00)
      new_band = create(:salary_band, pay_zone: zone, job_title: 'Manager', job_level: 'L5',
                        effective_from: Date.new(2025, 1, 1),
                        effective_to:   nil,
                        min_minor_units: 90_000_00,
                        mid_minor_units: 110_000_00,
                        max_minor_units: 140_000_00)

      scope = described_class.covering(Date.new(2024, 6, 1))
                             .where(pay_zone: zone, job_title: 'Manager', job_level: 'L5')
      expect(scope.first).to eq(old_band)

      scope2 = described_class.covering(Date.new(2025, 6, 1))
                              .where(pay_zone: zone, job_title: 'Manager', job_level: 'L5')
      expect(scope2.first).to eq(new_band)
    end
  end

  # ---------------------------------------------------------------------------
  # GIST overlap constraint
  # ---------------------------------------------------------------------------
  describe 'overlap constraint' do
    before do
      create(:salary_band, pay_zone: zone, job_title: 'Analyst', job_level: 'L3',
             effective_from: Date.new(2024, 1, 1), effective_to: nil)
    end

    it 'rejects an overlapping open-ended band for the same (zone, title, level)' do
      expect do
        described_class.create!(
          pay_zone: zone, job_title: 'Analyst', job_level: 'L3', currency: 'USD',
          min_minor_units: 80_000_00, mid_minor_units: 100_000_00, max_minor_units: 130_000_00,
          effective_from: Date.new(2025, 1, 1), effective_to: nil
        )
      end.to raise_error(ActiveRecord::StatementInvalid)
    end

    it 'allows a non-overlapping band that ends before the existing one starts' do
      expect do
        described_class.create!(
          pay_zone: zone, job_title: 'Analyst', job_level: 'L3', currency: 'USD',
          min_minor_units: 80_000_00, mid_minor_units: 100_000_00, max_minor_units: 130_000_00,
          effective_from: Date.new(2023, 1, 1), effective_to: Date.new(2024, 1, 1)
        )
      end.not_to raise_error
    end

    it 'allows bands for a different job_level in the same zone' do
      expect do
        described_class.create!(
          pay_zone: zone, job_title: 'Analyst', job_level: 'L5', currency: 'USD',
          min_minor_units: 100_000_00, mid_minor_units: 130_000_00, max_minor_units: 160_000_00,
          effective_from: Date.new(2024, 1, 1), effective_to: nil
        )
      end.not_to raise_error
    end
  end

  private

  def effective_from_plus_one_day(band)
    band.effective_from + 1
  end
end
