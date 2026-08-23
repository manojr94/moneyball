require 'rails_helper'

RSpec.describe Department, type: :model do
  describe 'validations' do
    it 'is valid with required attributes' do
      department = build(:department)
      expect(department).to be_valid
    end

    it 'requires a name' do
      department = build(:department, name: nil)
      expect(department).not_to be_valid
      expect(department.errors[:name]).to include("can't be blank")
    end

    it 'requires a unique name' do
      create(:department, name: 'Engineering', slug: 'engineering')
      duplicate = build(:department, name: 'Engineering', slug: 'engineering-2')
      expect(duplicate).not_to be_valid
      expect(duplicate.errors[:name]).to include('has already been taken')
    end

    it 'requires a slug' do
      department = build(:department, slug: nil, name: nil)
      expect(department).not_to be_valid
      expect(department.errors[:slug]).to include("can't be blank")
    end

    it 'requires a unique slug' do
      create(:department, name: 'Engineering', slug: 'engineering')
      duplicate = build(:department, name: 'Engineering Dept', slug: 'engineering')
      expect(duplicate).not_to be_valid
      expect(duplicate.errors[:slug]).to include('has already been taken')
    end

    it 'requires slug to match format' do
      department = build(:department, slug: 'Invalid Slug!')
      expect(department).not_to be_valid
      expect(department.errors[:slug]).to be_present
    end
  end

  describe 'slug auto-generation' do
    it 'generates a slug from the name before validation' do
      department = build(:department, name: 'Human Resources', slug: nil)
      department.valid?
      expect(department.slug).to eq('human-resources')
    end

    it 'converts special characters to hyphens' do
      department = build(:department, name: 'R&D Division', slug: nil)
      department.valid?
      expect(department.slug).to eq('r-d-division')
    end

    it 'does not overwrite a provided slug' do
      department = build(:department, name: 'Engineering', slug: 'eng')
      department.valid?
      expect(department.slug).to eq('eng')
    end
  end
end
