class Country < ApplicationRecord
  self.primary_key = 'code'

  belongs_to :pay_zone, optional: true
  has_many :employees, foreign_key: :country_code, primary_key: :code,
                       dependent: :restrict_with_error, inverse_of: :country

  REGIONS = %w[na latam emea apac].freeze

  validates :code, presence: true, uniqueness: true, length: { is: 2 }, format: { with: /\A[A-Z]{2}\z/ }
  validates :name, presence: true
  validates :default_currency, presence: true, length: { is: 3 }
  validates :region, presence: true, inclusion: { in: REGIONS }

  COUNTRY_DATA = YAML.load_file(Rails.root.join('db/data/countries.yml')).freeze

  def self.find_or_create_unconfigured(code)
    data = COUNTRY_DATA[code]
    return nil unless data

    record = find_or_initialize_by(code: code)
    return record unless record.new_record?

    write_unconfigured!(record, data)
  rescue ActiveRecord::RecordNotUnique
    find_by!(code: code)
  end

  private_class_method def self.write_unconfigured!(record, data)
    zone = PayZone.find_by(slug: "default-#{data['region']}")
    record.assign_attributes(
      name: data['name'],
      default_currency: data['default_currency'],
      region: data['region'],
      pay_zone: zone,
      needs_review: true
    )
    record.save!
    record
  end
end
