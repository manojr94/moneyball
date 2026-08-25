class User < ApplicationRecord
  has_secure_password

  ROLES = %w[hr_admin viewer].freeze

  before_validation { self.email = email&.downcase }

  validates :email, presence: true,
                    uniqueness: true,
                    format: { with: URI::MailTo::EMAIL_REGEXP }
  validates :name, presence: true
  validates :role, inclusion: { in: ROLES }

  scope :active, -> { where(active: true) }

  before_destroy do
    errors.add(:base, 'users may not be hard-deleted; deactivate instead')
    throw :abort
  end

  def hr_admin?
    role == 'hr_admin'
  end

  def viewer?
    role == 'viewer'
  end

  def deactivate!
    update!(token_version: token_version + 1, active: false)
  end

  def invalidate_tokens!
    update!(token_version: token_version + 1)
  end
end
