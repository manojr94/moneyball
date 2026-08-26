require 'rails_helper'

RSpec.describe 'GET /departments', type: :request do
  let(:admin)         { create(:user, :hr_admin) }
  let(:viewer)        { create(:user, :viewer) }
  let(:admin_headers) { { 'Authorization' => "Bearer #{AuthToken.encode(admin)}" } }
  let(:viewer_headers) { { 'Authorization' => "Bearer #{AuthToken.encode(viewer)}" } }

  before do
    create(:department, name: 'Engineering', slug: 'engineering')
    create(:department, name: 'Finance', slug: 'finance')
    create(:department, name: 'HR', slug: 'hr')
  end

  it 'returns 401 without a token' do
    get '/departments'
    expect(response).to have_http_status(:unauthorized)
  end

  it 'returns all departments ordered by name for an admin' do
    get '/departments', headers: admin_headers
    expect(response).to have_http_status(:ok)
    names = response.parsed_body.pluck('name')
    expect(names).to eq(names.sort)
    expect(names).to include('Engineering', 'Finance', 'HR')
  end

  it 'returns all departments for a viewer' do
    get '/departments', headers: viewer_headers
    expect(response).to have_http_status(:ok)
    body = response.parsed_body
    expect(body.first.keys).to include('id', 'name', 'slug')
  end
end
