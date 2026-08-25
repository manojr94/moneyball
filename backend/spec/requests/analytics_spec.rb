require 'rails_helper'

RSpec.describe 'Analytics API', type: :request do
  let(:admin)          { create(:user, :hr_admin) }
  let(:viewer)         { create(:user, :viewer) }
  let(:admin_headers)  { { 'Authorization' => "Bearer #{AuthToken.encode(admin)}" } }
  let(:viewer_headers) { { 'Authorization' => "Bearer #{AuthToken.encode(viewer)}" } }

  let(:zone) { create(:pay_zone) }
  let(:dept) { create(:department, name: 'Eng', slug: 'eng') }

  before do
    create(:country, code: 'US', name: 'US', default_currency: 'USD', region: 'na',   pay_zone: zone)
    create(:country, code: 'DE', name: 'DE', default_currency: 'EUR', region: 'emea', pay_zone: zone)
    ExchangeRate.create!(currency: 'EUR', rate_to_usd: '1.10', effective_date: Date.new(2024, 1, 1))
    e1 = create(:employee, employee_number: 'A1', country_code: 'US', department: dept,
                           job_level: 'L3', hire_date: '2020-01-01', email: 'a1@example.com')
    e2 = create(:employee, employee_number: 'A2', country_code: 'DE', department: dept,
                           job_level: 'L3', hire_date: '2020-01-01', email: 'a2@example.com')
    Salary.create!(employee: e1, amount_minor_units: 100_000_00, currency: 'USD',
                   effective_date: '2024-01-01', reason: 'new_hire')
    Salary.create!(employee: e2, amount_minor_units: 100_000_00, currency: 'EUR',
                   effective_date: '2024-01-01', reason: 'new_hire')
  end

  describe 'GET /analytics/pay' do
    it 'returns 401 without a token' do
      get '/analytics/pay', params: { group_by: 'region' }
      expect(response).to have_http_status(:unauthorized)
    end

    it 'returns 200 for a viewer (read-only allowed)' do
      get '/analytics/pay', params: { group_by: 'region', as_of: '2024-06-01' },
                            headers: viewer_headers
      expect(response).to have_http_status(:ok)
    end

    it 'returns 200 for an hr_admin' do
      get '/analytics/pay', params: { group_by: 'region', as_of: '2024-06-01' },
                            headers: admin_headers
      expect(response).to have_http_status(:ok)
    end

    it 'returns the expected response shape' do
      get '/analytics/pay', params: { group_by: 'region', as_of: '2024-06-01' },
                            headers: viewer_headers
      body = response.parsed_body
      expect(body).to have_key('groups')
      expect(body).to have_key('meta')
      expect(body['meta']).to include('as_of', 'rate_date', 'group_by', 'unconvertible_currencies')

      first = body['groups'].first
      expect(first.keys).to include(
        'key', 'label', 'headcount',
        'total_spend_usd_minor_units', 'min_usd_minor_units',
        'median_usd_minor_units', 'avg_usd_minor_units', 'max_usd_minor_units',
        'currency'
      )
      expect(first['currency']).to eq('USD')
    end

    it 'converts EUR at the rate_date' do
      get '/analytics/pay',
          params: { group_by: 'region', as_of: '2024-06-01', rate_date: '2024-06-01' },
          headers: viewer_headers
      groups = response.parsed_body['groups']
      emea = groups.find { |g| g['key'] == 'emea' }
      expect(emea['total_spend_usd_minor_units']).to eq(110_000_00)
    end

    it 'returns 422 for an unknown group_by' do
      get '/analytics/pay', params: { group_by: 'planet' }, headers: viewer_headers
      expect(response).to have_http_status(:unprocessable_content)
      expect(response.parsed_body['error']).to include('group_by must be one of')
    end

    it 'returns 422 for a malformed as_of' do
      get '/analytics/pay', params: { group_by: 'region', as_of: 'nope' },
                            headers: viewer_headers
      expect(response).to have_http_status(:unprocessable_content)
      expect(response.parsed_body['error']).to include('as_of')
    end

    it 'returns 422 for a malformed rate_date' do
      get '/analytics/pay', params: { group_by: 'region', rate_date: 'nope' },
                            headers: viewer_headers
      expect(response).to have_http_status(:unprocessable_content)
      expect(response.parsed_body['error']).to include('rate_date')
    end

    it 'returns 422 for an unknown region filter' do
      get '/analytics/pay', params: { group_by: 'region', region: 'antarctica' },
                            headers: viewer_headers
      expect(response).to have_http_status(:unprocessable_content)
    end

    it 'accepts filter combinations' do
      get '/analytics/pay',
          params: { group_by: 'country', region: 'emea', job_level: 'L3',
                    as_of: '2024-06-01' },
          headers: viewer_headers
      expect(response).to have_http_status(:ok)
      keys = response.parsed_body['groups'].pluck('key')
      expect(keys).to eq(['DE'])
    end
  end
end
