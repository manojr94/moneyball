zones = {
  'na' => 'North America',
  'latam' => 'Latin America',
  'emea' => 'EMEA',
  'apac' => 'APAC'
}

zone_records = zones.each_with_object({}) do |(region, name), acc|
  acc[region] = PayZone.find_or_create_by!(slug: "default-#{region}") { |z| z.name = name }
end

country_data = YAML.load_file(Rails.root.join('db/data/countries.yml'))
country_data.each do |code, attrs|
  zone = zone_records[attrs['region']]
  Country.find_or_create_by!(code: code) do |c|
    c.name             = attrs['name']
    c.default_currency = attrs['default_currency']
    c.region           = attrs['region']
    c.pay_zone         = zone
    c.needs_review     = false
  end
end

# M8 — Salary bands
# Six bands: Engineering L3 and L5 in three zones (NA/USD, EMEA/EUR, APAC/JPY).
# Intentionally leaves Designer L4 uncovered so the band_coverage report is non-empty.
# Idempotent via find_or_create_by! on (pay_zone_id, job_title, job_level, effective_from).

band_seed_date = Date.new(2024, 1, 1)

[
  { region: 'na',   title: 'Engineer', level: 'L3', currency: 'USD',
    min: 80_000_00, mid: 100_000_00, max: 130_000_00 },
  { region: 'na',   title: 'Engineer', level: 'L5', currency: 'USD',
    min: 130_000_00, mid: 160_000_00, max: 200_000_00 },
  { region: 'emea', title: 'Engineer', level: 'L3', currency: 'EUR',
    min: 70_000_00, mid: 90_000_00, max: 115_000_00 },
  { region: 'emea', title: 'Engineer', level: 'L5', currency: 'EUR',
    min: 110_000_00, mid: 140_000_00, max: 180_000_00 },
  { region: 'apac', title: 'Engineer', level: 'L3', currency: 'JPY',
    min: 7_000_000, mid: 9_000_000, max: 12_000_000 },
  { region: 'apac', title: 'Engineer', level: 'L5', currency: 'JPY',
    min: 12_000_000, mid: 16_000_000, max: 20_000_000 }
].each do |b|
  zone = zone_records[b[:region]]
  SalaryBand.find_or_create_by!(
    pay_zone_id: zone.id,
    job_title: b[:title],
    job_level: b[:level],
    effective_from: band_seed_date
  ) do |sb|
    sb.currency         = b[:currency]
    sb.min_minor_units  = b[:min]
    sb.mid_minor_units  = b[:mid]
    sb.max_minor_units  = b[:max]
    sb.effective_to     = nil
  end
end
