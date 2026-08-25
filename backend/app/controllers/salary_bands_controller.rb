class SalaryBandsController < ApplicationController
  def index
    authorize!(:read, policy_class: SalaryBandPolicy)
    bands = SalaryBand.covering(effective_on)
                      .then { |s| apply_filters(s) }
                      .includes(:pay_zone)
                      .order(:pay_zone_id, :job_title, :job_level)
    render json: bands.map { |b| serialize(b) }
  end

  def create
    authorize!(:write, policy_class: SalaryBandPolicy)
    band = SalaryBand.new(band_params)
    if band.valid?
      SalaryBand.transaction do
        close_previous_band(band)
        band.save!
      end
      render json: serialize(band), status: :created
    else
      render json: { errors: band.errors.full_messages }, status: :unprocessable_content
    end
  rescue ActiveRecord::StatementInvalid => e
    render json: { errors: [e.message.split("\n").first] }, status: :unprocessable_content
  end

  private

  def effective_on
    return Date.current if params[:effective_on].blank?

    Date.iso8601(params[:effective_on])
  rescue ArgumentError
    Date.current
  end

  def apply_filters(scope)
    scope = scope.where(pay_zone_id: params[:pay_zone_id]) if params[:pay_zone_id].present?
    scope = scope.where(job_title: params[:job_title])     if params[:job_title].present?
    scope = scope.where(job_level: params[:job_level])     if params[:job_level].present?
    scope
  end

  def close_previous_band(new_band)
    open_band = SalaryBand
                  .where(pay_zone_id: new_band.pay_zone_id,
                         job_title:   new_band.job_title,
                         job_level:   new_band.job_level,
                         effective_to: nil)
                  .first
    return unless open_band

    open_band.update!(effective_to: new_band.effective_from)
  end

  def band_params
    params.require(:salary_band).permit(
      :job_title, :job_level, :pay_zone_id, :currency,
      :min_minor_units, :mid_minor_units, :max_minor_units, :effective_from
    )
  end

  def serialize(band)
    { id: band.id, job_title: band.job_title, job_level: band.job_level,
      pay_zone_id: band.pay_zone_id, pay_zone_name: band.pay_zone&.name,
      currency: band.currency,
      min_minor_units: band.min_minor_units,
      mid_minor_units: band.mid_minor_units,
      max_minor_units: band.max_minor_units,
      effective_from: band.effective_from,
      effective_to:   band.effective_to }
  end
end
