require 'rails_helper'

RSpec.describe 'Sessions', type: :request do
  describe 'POST /session' do
    let!(:user) { create(:user, :hr_admin, email: 'admin@example.com', password: 'secret123') }

    it 'returns 201 and a token on valid credentials' do
      post '/session', params: { email: 'admin@example.com', password: 'secret123' }
      expect(response).to have_http_status(:created)
      body = response.parsed_body
      expect(body['token']).to be_present
      expect(body['user']['email']).to eq('admin@example.com')
      expect(body['user']['role']).to eq('hr_admin')
    end

    it 'is case-insensitive on email' do
      post '/session', params: { email: 'ADMIN@EXAMPLE.COM', password: 'secret123' }
      expect(response).to have_http_status(:created)
    end

    it 'returns 401 for a wrong password' do
      post '/session', params: { email: 'admin@example.com', password: 'wrong' }
      expect(response).to have_http_status(:unauthorized)
    end

    it 'returns 401 for an unknown email' do
      post '/session', params: { email: 'nobody@example.com', password: 'secret123' }
      expect(response).to have_http_status(:unauthorized)
    end

    it 'returns 401 for an inactive account' do
      user.deactivate!
      post '/session', params: { email: 'admin@example.com', password: 'secret123' }
      expect(response).to have_http_status(:unauthorized)
    end

    it 'updates last_sign_in_at on success' do
      freeze_time do
        post '/session', params: { email: 'admin@example.com', password: 'secret123' }
        expect(user.reload.last_sign_in_at).to be_within(1.second).of(Time.current)
      end
    end
  end

  describe 'DELETE /session' do
    let(:user) { create(:user) }
    let(:headers) { { 'Authorization' => "Bearer #{AuthToken.encode(user)}" } }

    it 'returns 204 and invalidates the token' do
      delete '/session', headers: headers
      expect(response).to have_http_status(:no_content)

      get '/me', headers: headers
      expect(response).to have_http_status(:unauthorized)
    end

    it 'returns 401 without a token' do
      delete '/session'
      expect(response).to have_http_status(:unauthorized)
    end
  end
end
