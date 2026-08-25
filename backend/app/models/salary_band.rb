class SalaryBand < ApplicationRecord
  belongs_to :pay_zone

  validates :job_title, :job_level, presence: true
  validates :currency, presence: true, format: { with: /\A[A-Z]{3}\z/ }
  validates :min_minor_units, :mid_minor_units, :max_minor_units,
            presence: true, numericality: { only_integer: true, greater_than: 0 }
  validates :effective_from, presence: true
  validates :effective_to, comparison: { greater_than: :effective_from }, allow_nil: true

  validate :currency_must_be_known
  validate :min_mid_max_ordering

  # Mutation policy: the only permitted update is setting effective_to from nil to a
  # date later than effective_from (i.e. "closing" the band when a new version opens).
  # Every other column is immutable after insert.
  before_update :guard_immutability

  scope :covering, lambda { |date|
    where('effective_from <= ? AND (effective_to IS NULL OR effective_to > ?)', date, date)
  }

  private

  def currency_must_be_known
    return if currency.blank?
    return if Money::Currency.find(currency)

    errors.add(:currency, "#{currency} is not a recognised ISO 4217 currency code")
  end

  def min_mid_max_ordering
    return unless min_minor_units && mid_minor_units && max_minor_units
    return if min_minor_units <= mid_minor_units && mid_minor_units <= max_minor_units

    errors.add(:base, 'min must be <= mid and mid must be <= max')
  end

  def guard_immutability
    mutable_attrs = %w[effective_to updated_at]
    changed_non_mutable = changes.keys - mutable_attrs
    return if changed_non_mutable.empty? && closing_effective_to?

    errors.add(:base, 'salary_band rows may only be closed (effective_to set from nil to a later date)')
    throw :abort
  end

  def closing_effective_to?
    return false unless changes.key?('effective_to')

    old_val, new_val = changes['effective_to']
    old_val.nil? && new_val.present? && new_val > effective_from
  end
end
