class Country < ApplicationRecord
  self.primary_key = 'code'

  belongs_to :pay_zone, optional: true
  has_many :employees, foreign_key: :country_code, primary_key: :code, dependent: :restrict_with_error

  REGIONS = %w[na latam emea apac].freeze

  validates :code, presence: true, uniqueness: true, length: { is: 2 }, format: { with: /\A[A-Z]{2}\z/ }
  validates :name, presence: true
  validates :default_currency, presence: true, length: { is: 3 }
  validates :region, presence: true, inclusion: { in: REGIONS }

  COUNTRY_DATA = YAML.load_file(Rails.root.join('db/data/countries.yml')).freeze

  def self.find_or_create_unconfigured(code)
    data = COUNTRY_DATA[code]
    return nil unless data

    find_or_initialize_by(code: code).tap do |c|
      next unless c.new_record?

      default_zone = PayZone.find_by(slug: "default-#{data['region']}")
      c.assign_attributes(
        name: data['name'],
        default_currency: data['default_currency'],
        region: data['region'],
        pay_zone: default_zone,
        needs_review: true
      )
      c.save!
    end
  end
end
