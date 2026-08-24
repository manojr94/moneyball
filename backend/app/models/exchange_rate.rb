class ExchangeRate < ApplicationRecord
  VALID_CURRENCY = /\A[A-Z]{3}\z/

  validates :currency, presence: true, format: { with: VALID_CURRENCY }
  validates :rate_to_usd, presence: true, numericality: { greater_than: 0 }
  validates :effective_date, presence: true

  before_update do
    errors.add(:base, 'exchange_rates rows are append-only and may not be updated')
    throw :abort
  end

  before_destroy do
    errors.add(:base, 'exchange_rates rows are append-only and may not be deleted')
    throw :abort
  end

  def self.as_of(currency, date)
    where(currency: currency.to_s.upcase)
      .where(effective_date: ..date)
      .order(effective_date: :desc)
      .first
  end
end
