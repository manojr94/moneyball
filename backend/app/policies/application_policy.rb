class ApplicationPolicy
  attr_reader :user, :record

  def initialize(user, record)
    @user = user
    @record = record
  end

  def read?
    user.present?
  end

  def write?
    user.present? && user.hr_admin?
  end
end
