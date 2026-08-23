class Employee < ApplicationRecord
  belongs_to :country, foreign_key: :country_code, primary_key: :code, inverse_of: :employees
  belongs_to :department

  STATUSES = %w[active inactive terminated].freeze

  validates :employee_number, presence: true, uniqueness: true
  validates :first_name, :last_name, :job_title, :job_level, presence: true
  validates :email, presence: true, uniqueness: true, format: { with: URI::MailTo::EMAIL_REGEXP }
  validates :hire_date, presence: true
  validates :country_code, presence: true
  validates :status, inclusion: { in: STATUSES }
  validate :terminated_on_requires_terminated_status

  scope :active, -> { where(status: 'active') }

  before_validation :ensure_country_exists
  before_destroy do
    errors.add(:base, 'employees may not be hard-deleted; use deactivate! or terminate!')
    throw :abort
  end

  def deactivate!
    update!(status: 'inactive')
  end

  def terminate!(on_date: Date.current)
    update!(status: 'terminated', terminated_on: on_date)
  end

  private

  def ensure_country_exists
    return if country_code.blank?
    return if Country.exists?(code: country_code)

    Country.find_or_create_unconfigured(country_code)
  end

  def terminated_on_requires_terminated_status
    return unless terminated_on.present? && status != 'terminated'

    errors.add(:terminated_on, 'can only be set when status is terminated')
  end
end
