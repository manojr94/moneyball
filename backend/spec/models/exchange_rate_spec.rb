require 'rails_helper'

RSpec.describe ExchangeRate, type: :model do
  subject(:rate) { build(:exchange_rate) }

  describe 'validations' do
    it { is_expected.to be_valid }

    it 'requires currency' do
      rate.currency = nil
      expect(rate).not_to be_valid
      expect(rate.errors[:currency]).to be_present
    end

    it 'requires currency to be 3 uppercase letters' do
      rate.currency = 'us'
      expect(rate).not_to be_valid
    end

    it 'rejects a 4-letter currency' do
      rate.currency = 'EURC'
      expect(rate).not_to be_valid
    end

    it 'rejects a numeric currency code' do
      rate.currency = '123'
      expect(rate).not_to be_valid
    end

    it 'requires rate_to_usd' do
      rate.rate_to_usd = nil
      expect(rate).not_to be_valid
    end

    it 'rejects a zero rate' do
      rate.rate_to_usd = 0
      expect(rate).not_to be_valid
      expect(rate.errors[:rate_to_usd]).to be_present
    end

    it 'rejects a negative rate' do
      rate.rate_to_usd = -1.08
      expect(rate).not_to be_valid
      expect(rate.errors[:rate_to_usd]).to be_present
    end

    it 'requires effective_date' do
      rate.effective_date = nil
      expect(rate).not_to be_valid
    end
  end

  describe 'append-only invariant' do
    let(:persisted) { create(:exchange_rate) }

    it 'cannot be updated' do
      persisted.rate_to_usd = 1.5
      expect(persisted.save).to be(false)
      expect(persisted.errors[:base]).to be_present
    end

    it 'cannot be destroyed' do
      expect(persisted.destroy).to be(false)
      expect(ExchangeRate.exists?(persisted.id)).to be(true)
    end

    it 'raises on destroy!' do
      expect { persisted.destroy! }.to raise_error(ActiveRecord::RecordNotDestroyed)
    end
  end

  describe '.as_of' do
    before do
      create(:exchange_rate, currency: 'JPY', rate_to_usd: '0.00654', effective_date: Date.new(2024, 1, 1))
      create(:exchange_rate, currency: 'JPY', rate_to_usd: '0.00680', effective_date: Date.new(2024, 3, 1))
    end

    it 'returns the rate on the exact date' do
      result = ExchangeRate.as_of('JPY', Date.new(2024, 3, 1))
      expect(result.rate_to_usd).to eq(BigDecimal('0.00680'))
    end

    it 'returns the most recent prior rate when no rate exists on the exact date' do
      result = ExchangeRate.as_of('JPY', Date.new(2024, 2, 15))
      expect(result.rate_to_usd).to eq(BigDecimal('0.00654'))
    end

    it 'returns nil when no rate exists on or before the date' do
      result = ExchangeRate.as_of('JPY', Date.new(2023, 12, 31))
      expect(result).to be_nil
    end

    it 'does not use a rate dated after the as-of date' do
      result = ExchangeRate.as_of('JPY', Date.new(2023, 12, 31))
      expect(result).to be_nil
    end
  end
end
