class Invitation < ApplicationRecord
  before_create { self.token = SecureRandom.urlsafe_base64(32) }

  scope :unused, -> { where(used_at: nil) }

  def use!
    update!(used_at: Time.current)
  end

  def used?
    used_at.present?
  end
end
