class CurrenciesController < ApplicationController
  def index
    authorize!(:read, policy_class: EmployeePolicy)
    currencies = Country.where.not(default_currency: nil)
                        .distinct
                        .pluck(:default_currency)
                        .sort
    render json: currencies
  end
end
