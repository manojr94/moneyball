require 'rails_helper'

RSpec.describe Country, type: :model do
  describe 'validations' do
    it 'is valid with required attributes' do
      country = build(:country)
      expect(country).to be_valid
    end

    it 'requires a code' do
      country = build(:country, code: nil)
      expect(country).not_to be_valid
      expect(country.errors[:code]).to be_present
    end

    it 'requires code to be exactly 2 characters' do
      country = build(:country, code: 'USA')
      expect(country).not_to be_valid
    end

    it 'requires code to be uppercase letters' do
      country = build(:country, code: 'us')
      expect(country).not_to be_valid
    end

    it 'requires a unique code' do
      create(:country, code: 'US')
      duplicate = build(:country, code: 'US')
      expect(duplicate).not_to be_valid
      expect(duplicate.errors[:code]).to include('has already been taken')
    end

    it 'requires a name' do
      country = build(:country, name: nil)
      expect(country).not_to be_valid
      expect(country.errors[:name]).to include("can't be blank")
    end

    it 'requires a default_currency' do
      country = build(:country, default_currency: nil)
      expect(country).not_to be_valid
      expect(country.errors[:default_currency]).to include("can't be blank")
    end

    it 'requires default_currency to be 3 characters' do
      country = build(:country, default_currency: 'US')
      expect(country).not_to be_valid
    end

    it 'requires a region' do
      country = build(:country, region: nil)
      expect(country).not_to be_valid
      expect(country.errors[:region]).to be_present
    end

    it 'rejects an invalid region value' do
      country = build(:country, region: 'invalid')
      expect(country).not_to be_valid
      expect(country.errors[:region]).to be_present
    end
  end

  describe 'associations' do
    it 'belongs to a pay_zone (optional)' do
      country = build(:country, pay_zone: nil)
      expect(country).to be_valid
    end

    it 'accepts a pay_zone' do
      zone = create(:pay_zone)
      country = build(:country, pay_zone: zone)
      expect(country).to be_valid
    end
  end

  describe '.find_or_create_unconfigured' do
    let!(:na_zone) { create(:pay_zone, name: 'North America', slug: 'default-na') }

    it 'creates a country marked needs_review when it does not exist' do
      country = Country.find_or_create_unconfigured('US')
      expect(country).to be_persisted
      expect(country.needs_review).to be true
      expect(country.code).to eq('US')
    end

    it 'returns the existing country without modification if it already exists' do
      existing = create(:country, code: 'US', needs_review: false)
      result = Country.find_or_create_unconfigured('US')
      expect(result.id).to eq(existing.id)
      expect(result.needs_review).to be false
    end

    it 'returns nil for an unknown country code' do
      result = Country.find_or_create_unconfigured('XX')
      expect(result).to be_nil
    end

    it 'assigns the matching default pay zone' do
      country = Country.find_or_create_unconfigured('US')
      expect(country.pay_zone).to eq(na_zone)
    end
  end
end
