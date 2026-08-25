require 'rails_helper'

RSpec.describe 'GET /analytics/compa_ratio', type: :request do
  let(:admin)          { create(:user, :hr_admin) }
  let(:viewer)         { create(:user, :viewer) }
  let(:admin_headers)  { { 'Authorization' => "Bearer #{AuthToken.encode(admin)}" } }
  let(:viewer_headers) { { 'Authorization' => "Bearer #{AuthToken.encode(viewer)}" } }

  let(:zone) { create(:pay_zone) }
  let(:dept) { create(:department) }

  before do
    create(:country, code: 'US', name: 'US', default_currency: 'USD', region: 'na', pay_zone: zone)
    e = create(:employee, employee_number: 'CR01', country_code: 'US', department: dept,
               job_title: 'Engineer', job_level: 'L3', hire_date: '2020-01-01',
               email: 'cr01@example.com')
    Salary.create!(employee: e, amount_minor_units: 100_000_00, currency: 'USD',
                   effective_date: '2020-01-01', reason: 'new_hire')
    create(:salary_band, pay_zone: zone, job_title: 'Engineer', job_level: 'L3',
           min_minor_units: 80_000_00, mid_minor_units: 100_000_00, max_minor_units: 130_000_00,
           effective_from: Date.new(2020, 1, 1))
  end

  it 'returns 401 without a token' do
    get '/analytics/compa_ratio', params: { group_by: 'region' }
    expect(response).to have_http_status(:unauthorized)
  end

  it 'returns 200 for a viewer' do
    get '/analytics/compa_ratio', params: { group_by: 'region', as_of: '2024-06-01' },
                                  headers: viewer_headers
    expect(response).to have_http_status(:ok)
  end

  it 'returns 200 for an hr_admin' do
    get '/analytics/compa_ratio', params: { group_by: 'region', as_of: '2024-06-01' },
                                  headers: admin_headers
    expect(response).to have_http_status(:ok)
  end

  it 'returns the expected response shape' do
    get '/analytics/compa_ratio', params: { group_by: 'region', as_of: '2024-06-01' },
                                  headers: viewer_headers
    body = response.parsed_body
    expect(body).to have_key('groups')
    expect(body).to have_key('meta')
    expect(body['meta'].keys).to include(
      'as_of', 'rate_date', 'group_by', 'unconvertible_currencies', 'uncovered_combinations'
    )
    row = body['groups'].first
    expect(row.keys).to include(
      'key', 'label', 'headcount', 'covered_headcount',
      'avg_compa_ratio', 'below', 'within', 'above', 'unresolved'
    )
  end

  it 'returns avg_compa_ratio as a 4-decimal-place string' do
    get '/analytics/compa_ratio', params: { group_by: 'region', as_of: '2024-06-01' },
                                  headers: viewer_headers
    ratio = response.parsed_body['groups'].first['avg_compa_ratio']
    expect(ratio).to match(/\A\d+\.\d{4}\z/)
  end

  it 'returns 422 for an unknown group_by' do
    get '/analytics/compa_ratio', params: { group_by: 'planet' }, headers: viewer_headers
    expect(response).to have_http_status(:unprocessable_content)
    expect(response.parsed_body['error']).to include('group_by must be one of')
  end

  it 'returns 422 for a malformed as_of' do
    get '/analytics/compa_ratio', params: { group_by: 'region', as_of: 'nope' },
                                  headers: viewer_headers
    expect(response).to have_http_status(:unprocessable_content)
    expect(response.parsed_body['error']).to include('as_of')
  end
end
