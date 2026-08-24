class FxConverter
  class UnknownCurrencyError < StandardError; end
  class NoRateError < StandardError; end

  # Convert amount_minor_units in from_currency to USD as of a given date.
  # Returns a Money object in USD.
  def self.convert(amount_minor_units:, from_currency:, as_of: Date.current)
    from = from_currency.to_s.upcase
    raise UnknownCurrencyError, "Unknown currency: #{from}" unless Money::Currency.find(from)

    return Money.new(amount_minor_units, 'USD') if from == 'USD'

    rate = ExchangeRate.as_of(from, as_of)
    raise NoRateError, "No exchange rate for #{from} on or before #{as_of}" if rate.nil?

    source = Money.new(amount_minor_units, from)
    usd_major = source.to_d * rate.rate_to_usd
    usd_minor = (usd_major * Money::Currency.find('USD').subunit_to_unit).round(0, BigDecimal::ROUND_HALF_UP).to_i
    Money.new(usd_minor, 'USD')
  end
end
