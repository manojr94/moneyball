class Salary < ApplicationRecord
  belongs_to :employee

  VALID_REASONS = %w[new_hire merit promotion correction role_change].freeze

  validates :amount_minor_units, presence: true,
                                 numericality: { only_integer: true, greater_than: 0 }
  validates :currency, presence: true, format: { with: /\A[A-Z]{3}\z/ }
  validates :effective_date, presence: true
  validates :reason, presence: true, inclusion: { in: VALID_REASONS }

  validate :currency_must_be_known

  # Blocks all updates, including touch. If a future association adds touch: true
  # on the Salary side, salary writes will abort unexpectedly. Remove the touch
  # before adding it.
  before_update do
    errors.add(:base, 'salary records are immutable; record a new row instead')
    throw :abort
  end

  before_destroy do
    errors.add(:base, 'salary records may not be deleted')
    throw :abort
  end

  scope :as_of, ->(date) { where(effective_date: ..date).order(effective_date: :desc, id: :desc) }

  def amount
    Money.new(amount_minor_units, currency)
  end

  private

  def currency_must_be_known
    return if currency.blank?
    return if Money::Currency.find(currency)

    errors.add(:currency, "#{currency} is not a recognised ISO 4217 currency code")
  end
end
