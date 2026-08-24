require 'rails_helper'

RSpec.describe FxConverter do
  describe '.convert' do
    let(:as_of) { Date.new(2024, 6, 1) }

    context 'with USD source' do
      it 'returns the amount unchanged as USD' do
        result = FxConverter.convert(amount_minor_units: 10_000, from_currency: 'USD', as_of: as_of)
        expect(result).to eq(Money.new(10_000, 'USD'))
      end
    end

    context 'with JPY (zero-decimal currency)' do
      before do
        # JPY has subunit_to_unit = 1: 1 minor unit = 1 yen
        create(:exchange_rate, currency: 'JPY', rate_to_usd: '0.00654', effective_date: as_of)
      end

      it 'converts JPY to USD using the correct exponent' do
        # 8_000_000 minor units of JPY = ¥8,000,000
        # ¥8,000,000 * 0.00654 = $52,320.00 = 5_232_000 cents
        result = FxConverter.convert(amount_minor_units: 8_000_000, from_currency: 'JPY', as_of: as_of)
        expect(result).to eq(Money.new(5_232_000, 'USD'))
      end
    end

    context 'with KWD (three-decimal currency)' do
      before do
        # KWD has subunit_to_unit = 1000: 1 dinar = 1000 fils
        create(:exchange_rate, currency: 'KWD', rate_to_usd: '3.25', effective_date: as_of)
      end

      it 'converts KWD to USD using the correct exponent' do
        # 1_000 minor units of KWD = KWD 1.000
        # KWD 1.000 * 3.25 = $3.25 = 325 cents
        result = FxConverter.convert(amount_minor_units: 1_000, from_currency: 'KWD', as_of: as_of)
        expect(result).to eq(Money.new(325, 'USD'))
      end

      it 'rounds fractional cents using ROUND_HALF_UP' do
        # KWD 1.000 * 3.333 = $3.333 → rounds to $3.33 (333 cents)
        create(:exchange_rate, currency: 'KWD', rate_to_usd: '3.333', effective_date: Date.new(2024, 7, 1))
        result = FxConverter.convert(amount_minor_units: 1_000, from_currency: 'KWD', as_of: Date.new(2024, 7, 1))
        expect(result).to eq(Money.new(333, 'USD'))
      end

      it 'rounds 0.5 cents up' do
        # KWD 1.000 * 3.335 = $3.335 → rounds to $3.34 (334 cents, ROUND_HALF_UP)
        create(:exchange_rate, currency: 'KWD', rate_to_usd: '3.335', effective_date: Date.new(2024, 8, 1))
        result = FxConverter.convert(amount_minor_units: 1_000, from_currency: 'KWD', as_of: Date.new(2024, 8, 1))
        expect(result).to eq(Money.new(334, 'USD'))
      end
    end

    context 'as-of date lookup' do
      before do
        create(:exchange_rate, currency: 'EUR', rate_to_usd: '1.08', effective_date: Date.new(2024, 1, 1))
        create(:exchange_rate, currency: 'EUR', rate_to_usd: '1.12', effective_date: Date.new(2024, 6, 1))
      end

      it 'uses the rate on the exact as-of date' do
        result = FxConverter.convert(amount_minor_units: 100, from_currency: 'EUR', as_of: Date.new(2024, 6, 1))
        # EUR 1.00 * 1.12 = $1.12 = 112 cents
        expect(result).to eq(Money.new(112, 'USD'))
      end

      it 'falls back to the most recent prior rate when no rate exists on the exact date' do
        result = FxConverter.convert(amount_minor_units: 100, from_currency: 'EUR', as_of: Date.new(2024, 3, 15))
        # EUR 1.00 * 1.08 (from Jan 1) = $1.08 = 108 cents
        expect(result).to eq(Money.new(108, 'USD'))
      end

      it 'raises NoRateError when no rate exists on or before the as-of date' do
        expect do
          FxConverter.convert(amount_minor_units: 100, from_currency: 'EUR', as_of: Date.new(2023, 12, 31))
        end.to raise_error(FxConverter::NoRateError)
      end

      it 'does not use a rate dated after the as-of date' do
        expect do
          FxConverter.convert(amount_minor_units: 100, from_currency: 'EUR', as_of: Date.new(2023, 6, 1))
        end.to raise_error(FxConverter::NoRateError)
      end
    end

    context 'error cases' do
      it 'raises UnknownCurrencyError for an unrecognized currency code' do
        expect do
          FxConverter.convert(amount_minor_units: 100, from_currency: 'XYZ', as_of: as_of)
        end.to raise_error(FxConverter::UnknownCurrencyError, /XYZ/)
      end

      it 'raises NoRateError when the currency is known but has no rate at all' do
        expect do
          FxConverter.convert(amount_minor_units: 100, from_currency: 'GBP', as_of: as_of)
        end.to raise_error(FxConverter::NoRateError, /GBP/)
      end
    end
  end
end
