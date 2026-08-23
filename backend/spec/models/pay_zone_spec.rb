require 'rails_helper'

RSpec.describe PayZone, type: :model do
  describe 'validations' do
    it 'is valid with required attributes' do
      pay_zone = build(:pay_zone)
      expect(pay_zone).to be_valid
    end

    it 'requires a name' do
      pay_zone = build(:pay_zone, name: nil)
      expect(pay_zone).not_to be_valid
      expect(pay_zone.errors[:name]).to include("can't be blank")
    end

    it 'requires a slug' do
      pay_zone = build(:pay_zone, slug: nil, name: nil)
      expect(pay_zone).not_to be_valid
      expect(pay_zone.errors[:slug]).to include("can't be blank")
    end

    it 'requires a unique name' do
      create(:pay_zone, name: 'North America', slug: 'north-america')
      duplicate = build(:pay_zone, name: 'North America', slug: 'north-america-2')
      expect(duplicate).not_to be_valid
      expect(duplicate.errors[:name]).to include('has already been taken')
    end

    it 'requires a unique slug' do
      create(:pay_zone, name: 'North America', slug: 'north-america')
      duplicate = build(:pay_zone, name: 'North America 2', slug: 'north-america')
      expect(duplicate).not_to be_valid
      expect(duplicate.errors[:slug]).to include('has already been taken')
    end

    it 'requires slug to match format' do
      pay_zone = build(:pay_zone, slug: 'Invalid Slug!')
      expect(pay_zone).not_to be_valid
      expect(pay_zone.errors[:slug]).to be_present
    end
  end

  describe 'slug auto-generation' do
    it 'generates a slug from the name before validation' do
      pay_zone = build(:pay_zone, name: 'North America', slug: nil)
      pay_zone.valid?
      expect(pay_zone.slug).to eq('north-america')
    end

    it 'converts spaces and special characters to hyphens' do
      pay_zone = build(:pay_zone, name: 'Asia & Pacific', slug: nil)
      pay_zone.valid?
      expect(pay_zone.slug).to eq('asia-pacific')
    end

    it 'does not overwrite a provided slug' do
      pay_zone = build(:pay_zone, name: 'North America', slug: 'custom-slug')
      pay_zone.valid?
      expect(pay_zone.slug).to eq('custom-slug')
    end
  end
end
