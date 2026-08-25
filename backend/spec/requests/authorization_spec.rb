require 'rails_helper'

RSpec.describe 'Authorization enforcement', type: :request do
  describe 'unauthenticated access' do
    it 'returns 401 with no token' do
      get '/me'
      expect(response).to have_http_status(:unauthorized)
    end

    it 'returns 401 with a malformed token' do
      get '/me', headers: { 'Authorization' => 'Bearer not.a.real.token' }
      expect(response).to have_http_status(:unauthorized)
    end

    it 'returns 401 with an expired token' do
      user = create(:user)
      token = travel_to(25.hours.ago) { AuthToken.encode(user) }
      get '/me', headers: { 'Authorization' => "Bearer #{token}" }
      expect(response).to have_http_status(:unauthorized)
    end

    it 'returns 401 after token invalidation (sign-out)' do
      user = create(:user)
      token = AuthToken.encode(user)
      user.invalidate_tokens!
      get '/me', headers: { 'Authorization' => "Bearer #{token}" }
      expect(response).to have_http_status(:unauthorized)
    end

    it 'returns 401 for a deactivated user' do
      user = create(:user)
      user.deactivate!
      user.reload
      # Encode at the updated token_version to bypass the version check,
      # proving the active flag is also enforced independently.
      fresh_token = AuthToken.encode(user)
      get '/me', headers: { 'Authorization' => "Bearer #{fresh_token}" }
      expect(response).to have_http_status(:unauthorized)
    end
  end

  describe 'authenticated but unauthorized (viewer on write path)' do
    let(:viewer) { create(:user, :viewer) }
    let(:headers) { { 'Authorization' => "Bearer #{AuthToken.encode(viewer)}" } }

    it 'returns 403 for a viewer on a write endpoint' do
      post '/probes/write', headers: headers
      expect(response).to have_http_status(:forbidden)
    end
  end

  describe 'hr_admin on a write endpoint' do
    let(:admin) { create(:user, :hr_admin) }
    let(:headers) { { 'Authorization' => "Bearer #{AuthToken.encode(admin)}" } }

    it 'returns 200' do
      post '/probes/write', headers: headers
      expect(response).to have_http_status(:ok)
    end
  end

  describe 'GET /me' do
    it 'returns current user info for an authenticated user' do
      user = create(:user, :hr_admin, name: 'Alice', email: 'alice@example.com')
      get '/me', headers: { 'Authorization' => "Bearer #{AuthToken.encode(user)}" }
      expect(response).to have_http_status(:ok)
      body = response.parsed_body
      expect(body['email']).to eq('alice@example.com')
      expect(body['role']).to eq('hr_admin')
    end
  end
end
