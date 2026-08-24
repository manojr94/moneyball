require 'rails_helper'

RSpec.describe User, type: :model do
  describe 'validations' do
    it 'is valid with valid attributes' do
      expect(build(:user)).to be_valid
    end

    it 'requires an email' do
      expect(build(:user, email: nil)).not_to be_valid
    end

    it 'requires a unique email (case-insensitive)' do
      create(:user, email: 'admin@example.com')
      expect(build(:user, email: 'ADMIN@example.com')).not_to be_valid
    end

    it 'requires a valid email format' do
      expect(build(:user, email: 'not-an-email')).not_to be_valid
    end

    it 'requires a name' do
      expect(build(:user, name: nil)).not_to be_valid
    end

    it 'requires a known role' do
      expect(build(:user, role: 'superuser')).not_to be_valid
    end

    it 'accepts hr_admin role' do
      expect(build(:user, :hr_admin)).to be_valid
    end

    it 'accepts viewer role' do
      expect(build(:user, :viewer)).to be_valid
    end
  end

  describe '#hr_admin? / #viewer?' do
    it 'returns true for hr_admin' do
      expect(build(:user, :hr_admin)).to be_hr_admin
      expect(build(:user, :hr_admin)).not_to be_viewer
    end

    it 'returns true for viewer' do
      expect(build(:user, :viewer)).to be_viewer
      expect(build(:user, :viewer)).not_to be_hr_admin
    end
  end

  describe '#deactivate!' do
    it 'sets active to false and bumps token_version' do
      user = create(:user)
      original_version = user.token_version
      user.deactivate!
      user.reload
      expect(user.active).to be false
      expect(user.token_version).to eq(original_version + 1)
    end
  end

  describe '#invalidate_tokens!' do
    it 'bumps token_version without deactivating the account' do
      user = create(:user)
      original_version = user.token_version
      user.invalidate_tokens!
      user.reload
      expect(user.token_version).to eq(original_version + 1)
      expect(user.active).to be true
    end
  end

  describe 'hard-delete guard' do
    it 'prevents destroy' do
      user = create(:user)
      expect(user.destroy).to be false
    end

    it 'raises on destroy!' do
      user = create(:user)
      expect { user.destroy! }.to raise_error(ActiveRecord::RecordNotDestroyed)
    end
  end
end
