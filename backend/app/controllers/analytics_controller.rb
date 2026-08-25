class AnalyticsController < ApplicationController
  def pay
    authorize!(:read)
    query = PayAnalytics.new(query_params)
    return render json: { error: query.error }, status: :unprocessable_content unless query.valid?

    render json: query.call
  end

  private

  def query_params
    params.permit(:group_by, :as_of, :rate_date,
                  :region, :country_code, :department_id, :job_level)
  end
end
