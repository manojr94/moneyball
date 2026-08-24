class FxConverter
  class UnknownCurrencyError < StandardError; end
  class NoRateError < StandardError; end

  def self.convert(amount_minor_units:, from_currency:, as_of:)
    from = from_currency.to_s.upcase
    raise UnknownCurrencyError, "Unknown currency: #{from}" unless Money::Currency.find(from)

    return Money.new(amount_minor_units, 'USD') if from == 'USD'

    rate = ExchangeRate.as_of(from, as_of)
    raise NoRateError, "No exchange rate for #{from} on or before #{as_of}" if rate.nil?

    to_usd(amount_minor_units, from, rate.rate_to_usd)
  end

  def self.to_usd(amount_minor_units, currency, rate_to_usd)
    source = Money.new(amount_minor_units, currency)
    usd_major = source.to_d * rate_to_usd
    usd_minor = (usd_major * Money::Currency.find('USD').subunit_to_unit).round(0, BigDecimal::ROUND_HALF_UP).to_i
    Money.new(usd_minor, 'USD')
  end
  private_class_method :to_usd
end
