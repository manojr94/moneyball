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
