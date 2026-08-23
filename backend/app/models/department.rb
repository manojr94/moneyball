class Department < ApplicationRecord
  has_many :employees, dependent: :restrict_with_error

  validates :name, presence: true, uniqueness: true
  validates :slug, presence: true, uniqueness: true, format: { with: /\A[a-z0-9-]+\z/ }

  before_validation :generate_slug, if: -> { slug.blank? && name.present? }

  private

  def generate_slug
    self.slug = name.downcase.gsub(/[^a-z0-9]+/, '-').gsub(/(^-|-$)/, '')
  end
end
