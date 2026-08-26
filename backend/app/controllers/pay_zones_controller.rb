class PayZonesController < ApplicationController
  def index
    authorize!(:read)
    pay_zones = PayZone.order(:name)
    render json: pay_zones.map { |z| { id: z.id, name: z.name, slug: z.slug } }
  end
end
