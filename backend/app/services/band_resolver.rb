class BandResolver
  Result = Struct.new(
    :band, :reason, :compa_ratio,
    :bucket,
    :salary_usd_minor_units,
    :band_min_usd_minor_units,
    :band_mid_usd_minor_units,
    :band_max_usd_minor_units,
    keyword_init: true
  )

  # Resolve band and compa-ratio for an employee on a given date.
  #
  # Returns a Result with:
  #   reason:      :ok | :no_salary | :unzoned_country | :no_band | :no_rate
  #   compa_ratio: BigDecimal (salary_usd / mid_usd), nil if unresolved
  #   bucket:      :below | :within | :above | nil
  #
  # Raises only for programmer errors (nil employee, nil on_date).
  def self.resolve(employee:, on_date:, rate_date: on_date)
    raise ArgumentError, 'employee is required' if employee.nil?
    raise ArgumentError, 'on_date is required'  if on_date.nil?

    salary = employee.salary_on(on_date)
    return unresolved(:no_salary) if salary.nil?

    pay_zone_id = employee.country&.pay_zone_id
    return unresolved(:unzoned_country) if pay_zone_id.nil?

    band = SalaryBand.covering(on_date)
                     .find_by(pay_zone_id:,
                              job_title: employee.job_title,
                              job_level: employee.job_level)
    return unresolved(:no_band) if band.nil?

    salary_usd = convert(salary.amount_minor_units, salary.currency, rate_date)
    return unresolved(:no_rate) if salary_usd.nil?

    band_min_usd = convert(band.min_minor_units, band.currency, rate_date)
    band_mid_usd = convert(band.mid_minor_units, band.currency, rate_date)
    band_max_usd = convert(band.max_minor_units, band.currency, rate_date)
    return unresolved(:no_rate) if band_min_usd.nil? || band_mid_usd.nil? || band_max_usd.nil?

    sal = salary_usd.fractional
    min = band_min_usd.fractional
    mid = band_mid_usd.fractional
    max = band_max_usd.fractional

    compa_ratio = mid.positive? ? BigDecimal(sal.to_s) / BigDecimal(mid.to_s) : nil
    bucket = bucket_for(sal, min, max)

    Result.new(
      band:                    band,
      reason:                  :ok,
      compa_ratio:             compa_ratio,
      bucket:                  bucket,
      salary_usd_minor_units:  sal,
      band_min_usd_minor_units: min,
      band_mid_usd_minor_units: mid,
      band_max_usd_minor_units: max
    )
  end

  private_class_method def self.unresolved(reason)
    Result.new(band: nil, reason:, compa_ratio: nil, bucket: nil,
               salary_usd_minor_units: nil,
               band_min_usd_minor_units: nil,
               band_mid_usd_minor_units: nil,
               band_max_usd_minor_units: nil)
  end

  private_class_method def self.convert(amount_minor_units, currency, rate_date)
    FxConverter.convert(amount_minor_units:, from_currency: currency, as_of: rate_date)
  rescue FxConverter::NoRateError
    nil
  end

  private_class_method def self.bucket_for(salary_usd, min_usd, max_usd)
    if salary_usd < min_usd
      :below
    elsif salary_usd > max_usd
      :above
    else
      :within
    end
  end
end
