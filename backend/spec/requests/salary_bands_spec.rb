require 'rails_helper'

RSpec.describe 'Salary Bands API', type: :request do
  let(:admin)          { create(:user, :hr_admin) }
  let(:viewer)         { create(:user, :viewer) }
  let(:admin_headers)  { { 'Authorization' => "Bearer #{AuthToken.encode(admin)}" } }
  let(:viewer_headers) { { 'Authorization' => "Bearer #{AuthToken.encode(viewer)}" } }

  let(:zone) { create(:pay_zone, name: 'North America', slug: 'na') }
  let(:zone2) { create(:pay_zone, name: 'EMEA', slug: 'emea') }

  let(:valid_params) do
    { salary_band: { pay_zone_id: zone.id, job_title: 'Engineer', job_level: 'L3',
                     currency: 'USD', min_minor_units: 80_000_00,
                     mid_minor_units: 100_000_00, max_minor_units: 130_000_00,
                     effective_from: '2024-01-01' } }
  end

  # ---------------------------------------------------------------------------
  # GET /salary_bands
  # ---------------------------------------------------------------------------
  describe 'GET /salary_bands' do
    before do
      create(:salary_band, :current, pay_zone: zone, job_title: 'Engineer', job_level: 'L3')
      create(:salary_band, :closed,  pay_zone: zone, job_title: 'Manager',  job_level: 'L5')
    end

    it 'returns 401 without a token' do
      get '/salary_bands'
      expect(response).to have_http_status(:unauthorized)
    end

    it 'returns 200 for a viewer' do
      get '/salary_bands', headers: viewer_headers
      expect(response).to have_http_status(:ok)
    end

    it 'returns 200 for an hr_admin' do
      get '/salary_bands', headers: admin_headers
      expect(response).to have_http_status(:ok)
    end

    it 'returns only bands covering today by default' do
      get '/salary_bands', headers: viewer_headers
      ids = response.parsed_body.pluck('id')
      all_ids = SalaryBand.pluck(:id)
      covering_ids = SalaryBand.covering(Date.current).pluck(:id)
      expect(ids).to match_array(covering_ids)
      expect(ids.length).to be < all_ids.length
    end

    it 'includes pay_zone_name in the response' do
      get '/salary_bands', headers: viewer_headers
      expect(response.parsed_body.first).to have_key('pay_zone_name')
    end

    it 'filters by pay_zone_id' do
      create(:salary_band, :current, pay_zone: zone2, job_title: 'Analyst', job_level: 'L2')
      get '/salary_bands', params: { pay_zone_id: zone2.id }, headers: viewer_headers
      pay_zone_ids = response.parsed_body.pluck('pay_zone_id')
      expect(pay_zone_ids).to all(eq(zone2.id))
    end

    it 'filters by job_title' do
      get '/salary_bands', params: { job_title: 'Engineer' }, headers: viewer_headers
      titles = response.parsed_body.pluck('job_title')
      expect(titles).to all(eq('Engineer'))
    end

    it 'filters by job_level' do
      create(:salary_band, :current, pay_zone: zone, job_title: 'Analyst', job_level: 'L5')
      get '/salary_bands', params: { job_level: 'L3' }, headers: viewer_headers
      levels = response.parsed_body.pluck('job_level')
      expect(levels).to all(eq('L3'))
    end
  end

  # ---------------------------------------------------------------------------
  # POST /salary_bands
  # ---------------------------------------------------------------------------
  describe 'POST /salary_bands' do
    it 'returns 401 without a token' do
      post '/salary_bands', params: valid_params, as: :json
      expect(response).to have_http_status(:unauthorized)
    end

    it 'returns 403 for a viewer' do
      post '/salary_bands', params: valid_params, as: :json, headers: viewer_headers
      expect(response).to have_http_status(:forbidden)
    end

    it 'creates a band and returns 201 for hr_admin' do
      expect do
        post '/salary_bands', params: valid_params, as: :json, headers: admin_headers
      end.to change(SalaryBand, :count).by(1)
      expect(response).to have_http_status(:created)
    end

    it 'returns the created band with the expected shape' do
      post '/salary_bands', params: valid_params, as: :json, headers: admin_headers
      body = response.parsed_body
      expect(body.keys).to include('id', 'job_title', 'job_level', 'pay_zone_id',
                                   'pay_zone_name', 'currency',
                                   'min_minor_units', 'mid_minor_units', 'max_minor_units',
                                   'effective_from', 'effective_to')
      expect(body['effective_to']).to be_nil
    end

    it 'returns 422 for max < min' do
      bad_params = valid_params.deep_merge(salary_band: { max_minor_units: 50_000_00 })
      post '/salary_bands', params: bad_params, as: :json, headers: admin_headers
      expect(response).to have_http_status(:unprocessable_content)
      expect(response.parsed_body['errors'].join).to include('min')
    end

    it 'returns 422 for an unknown currency' do
      bad_params = valid_params.deep_merge(salary_band: { currency: 'XYZ' })
      post '/salary_bands', params: bad_params, as: :json, headers: admin_headers
      expect(response).to have_http_status(:unprocessable_content)
    end

    context 'when auto-closing the previous open band' do
      let!(:existing) do
        create(:salary_band, pay_zone: zone, job_title: 'Engineer', job_level: 'L3',
                             currency: 'USD', min_minor_units: 70_000_00,
                             mid_minor_units: 90_000_00, max_minor_units: 120_000_00,
                             effective_from: Date.new(2023, 1, 1), effective_to: nil)
      end

      it 'closes the previous open band and creates the new one' do
        post '/salary_bands',
             params: valid_params,
             as: :json, headers: admin_headers
        expect(response).to have_http_status(:created)
        expect(existing.reload.effective_to).to eq(Date.new(2024, 1, 1))
        expect(SalaryBand.covering(Date.new(2024, 6, 1))
                         .where(pay_zone: zone, job_title: 'Engineer', job_level: 'L3')
                         .count).to eq(1)
      end
    end

    it 'returns 422 when a band with the same (zone, title, level, effective_from) exists' do
      create(:salary_band, pay_zone: zone, job_title: 'Engineer', job_level: 'L3',
                           currency: 'USD', min_minor_units: 70_000_00, mid_minor_units: 90_000_00,
                           max_minor_units: 120_000_00, effective_from: Date.new(2024, 1, 1),
                           effective_to: nil)
      post '/salary_bands', params: valid_params, as: :json, headers: admin_headers
      expect(response).to have_http_status(:unprocessable_content)
    end
  end
end
