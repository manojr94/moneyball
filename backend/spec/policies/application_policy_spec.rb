require 'rails_helper'

RSpec.describe ApplicationPolicy do
  let(:hr_admin) { build(:user, :hr_admin) }
  let(:viewer)   { build(:user, :viewer) }

  describe '#read?' do
    it 'allows an hr_admin' do
      expect(described_class.new(hr_admin, nil).read?).to be true
    end

    it 'allows a viewer' do
      expect(described_class.new(viewer, nil).read?).to be true
    end

    it 'denies nil (unauthenticated)' do
      expect(described_class.new(nil, nil).read?).to be false
    end
  end

  describe '#write?' do
    it 'allows an hr_admin' do
      expect(described_class.new(hr_admin, nil).write?).to be true
    end

    it 'denies a viewer' do
      expect(described_class.new(viewer, nil).write?).to be false
    end

    it 'denies nil (unauthenticated)' do
      expect(described_class.new(nil, nil).write?).to be false
    end
  end
end
