class Country < ApplicationRecord
  self.primary_key = 'code'

  belongs_to :pay_zone, optional: true
  has_many :employees, foreign_key: :country_code, primary_key: :code,
                       dependent: :restrict_with_error, inverse_of: :country

  REGIONS = %w[na latam emea apac].freeze

  validates :code, presence: true, uniqueness: true, length: { is: 2 }, format: { with: /\A[A-Z]{2}\z/ }
  validates :name, presence: true, unless: :needs_review?
  validates :default_currency, presence: true, unless: :needs_review?
  validates :default_currency, length: { is: 3 }, allow_blank: true
  validates :region, presence: true, unless: :needs_review?
  validates :region, inclusion: { in: REGIONS }, allow_nil: true

  COUNTRY_DATA = YAML.load_file(Rails.root.join('db/data/countries.yml')).freeze

  def self.find_or_create_unconfigured(code)
    record = find_or_initialize_by(code: code)
    return record unless record.new_record?

    data = COUNTRY_DATA[code]
    data ? write_unconfigured!(record, data) : write_unknown!(record)
  rescue ActiveRecord::RecordNotUnique
    find_by!(code: code)
  end

  private_class_method def self.write_unknown!(record)
    record.needs_review = true
    record.save!
    record
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
