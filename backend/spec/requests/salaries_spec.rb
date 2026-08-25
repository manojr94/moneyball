require 'rails_helper'

RSpec.describe 'Salaries API', type: :request do
  let(:admin)          { create(:user, :hr_admin) }
  let(:viewer)         { create(:user, :viewer) }
  let(:admin_headers)  { { 'Authorization' => "Bearer #{AuthToken.encode(admin)}" } }
  let(:viewer_headers) { { 'Authorization' => "Bearer #{AuthToken.encode(viewer)}" } }

  let!(:employee) { create(:employee) }
  let!(:salary)   { create(:salary, employee: employee, amount_minor_units: 8_000_000, currency: 'USD') }

  # ---------------------------------------------------------------------------
  # GET /employees/:id/salaries
  # ---------------------------------------------------------------------------
  describe 'GET /employees/:id/salaries' do
    it 'returns 401 without a token' do
      get "/employees/#{employee.id}/salaries"
      expect(response).to have_http_status(:unauthorized)
    end

    it 'returns 200 with an array of salaries for a viewer' do
      get "/employees/#{employee.id}/salaries", headers: viewer_headers
      expect(response).to have_http_status(:ok)
      body = response.parsed_body
      expect(body).to be_an(Array)
      expect(body.first).to include(
        'id' => salary.id,
        'employee_id' => employee.id,
        'amount_minor_units' => 8_000_000,
        'currency' => 'USD'
      )
    end

    it 'returns salaries newest-first' do
      recent = create(:salary, employee: employee, amount_minor_units: 9_000_000,
                               currency: 'USD', effective_date: Date.current)
      old    = create(:salary, employee: employee, amount_minor_units: 7_000_000,
                               currency: 'USD', effective_date: 5.years.ago.to_date)
      get "/employees/#{employee.id}/salaries", headers: viewer_headers
      body = response.parsed_body
      ids = body.pluck('id')
      expect(ids.index(recent.id)).to be < ids.index(old.id)
    end

    it 'returns 404 for unknown employee' do
      get '/employees/999999/salaries', headers: viewer_headers
      expect(response).to have_http_status(:not_found)
    end
  end

  # ---------------------------------------------------------------------------
  # POST /employees/:id/salaries
  # ---------------------------------------------------------------------------
  describe 'POST /employees/:id/salaries' do
    let(:valid_params) do
      {
        salary: {
          amount_minor_units: 9_000_000,
          currency: 'USD',
          effective_date: Date.current.to_s,
          reason: 'merit'
        }
      }
    end

    it 'returns 401 without a token' do
      post "/employees/#{employee.id}/salaries", params: valid_params, as: :json
      expect(response).to have_http_status(:unauthorized)
    end

    it 'returns 403 for a viewer' do
      post "/employees/#{employee.id}/salaries", params: valid_params,
                                                 headers: viewer_headers, as: :json
      expect(response).to have_http_status(:forbidden)
    end

    it 'creates a salary and returns 201 for an admin' do
      expect do
        post "/employees/#{employee.id}/salaries", params: valid_params,
                                                   headers: admin_headers, as: :json
      end.to change(Salary, :count).by(1)
      expect(response).to have_http_status(:created)
      body = response.parsed_body
      expect(body).to include('amount_minor_units' => 9_000_000, 'currency' => 'USD')
    end

    it 'does not mutate the existing salary row (effective-dated immutability)' do
      post "/employees/#{employee.id}/salaries", params: valid_params,
                                                 headers: admin_headers, as: :json
      expect(salary.reload.amount_minor_units).to eq(8_000_000)
    end

    it 'records the current_user as created_by' do
      post "/employees/#{employee.id}/salaries", params: valid_params,
                                                 headers: admin_headers, as: :json
      expect(Salary.last.created_by_id).to eq(admin.id)
    end

    it 'returns 422 for invalid salary data' do
      bad_params = { salary: { amount_minor_units: -1, currency: 'USD',
                               effective_date: Date.current.to_s, reason: 'merit' } }
      post "/employees/#{employee.id}/salaries", params: bad_params,
                                                 headers: admin_headers, as: :json
      expect(response).to have_http_status(:unprocessable_content)
      expect(response.parsed_body).to have_key('errors')
    end

    it 'returns 404 for unknown employee' do
      post '/employees/999999/salaries', params: valid_params, headers: admin_headers, as: :json
      expect(response).to have_http_status(:not_found)
    end
  end
end
