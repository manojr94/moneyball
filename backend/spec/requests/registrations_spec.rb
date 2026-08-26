require 'rails_helper'

RSpec.describe 'POST /registrations', type: :request do
  let(:valid_params) do
    { name: 'Jane Doe', email: 'jane@example.com', password: 'password123' }
  end

  def post_signup(extra = {})
    post '/registrations', params: valid_params.merge(extra)
  end

  describe 'valid unused token + valid params' do
    let!(:invitation) { create(:invitation) }

    it 'returns 201, creates an hr_admin user, and marks the token used' do
      post_signup(token: invitation.token)

      expect(response).to have_http_status(:created)
      body = response.parsed_body
      expect(body).to have_key('token')
      expect(body['user']['role']).to eq('hr_admin')
      expect(body['user']['email']).to eq('jane@example.com')
      expect(invitation.reload.used?).to be true
    end

    it 'ignores a role param and always creates an hr_admin user' do
      post_signup(token: invitation.token, role: 'viewer')

      expect(response).to have_http_status(:created)
      expect(User.last.role).to eq('hr_admin')
    end
  end

  describe 'valid unused token + duplicate email' do
    let!(:invitation) { create(:invitation) }

    before { create(:user, email: 'jane@example.com') }

    it 'returns 422, does not create a user, and does not consume the token' do
      post_signup(token: invitation.token)

      expect(response).to have_http_status(:unprocessable_content)
      expect(response.parsed_body).to have_key('errors')
      expect(invitation.reload.used?).to be false
    end
  end

  describe 'already-used token' do
    let!(:invitation) { create(:invitation, :used) }

    it 'returns 422 with the expected message' do
      post_signup(token: invitation.token)

      expect(response).to have_http_status(:unprocessable_content)
      expect(response.parsed_body['error']).to include('invalid or has already been used')
    end
  end

  describe 'missing token' do
    it 'returns 422 with the expected message' do
      post_signup(token: nil)

      expect(response).to have_http_status(:unprocessable_content)
      expect(response.parsed_body['error']).to include('invalid or has already been used')
    end
  end

  describe 'valid token + blank name' do
    let!(:invitation) { create(:invitation) }

    it 'returns 422, does not create a user, and does not consume the token' do
      post '/registrations', params: valid_params.merge(token: invitation.token, name: '')

      expect(response).to have_http_status(:unprocessable_content)
      expect(response.parsed_body).to have_key('errors')
      expect(invitation.reload.used?).to be false
    end
  end

  describe 'concurrent requests on same token' do
    it 'allows only one signup to succeed' do
      invitation = create(:invitation)
      results = []
      threads = 2.times.map do |i|
        Thread.new do
          post '/registrations',
               params: valid_params.merge(token: invitation.token,
                                          email: "concurrent#{i}@example.com")
          results << response.status
        end
      end
      threads.each(&:join)

      expect(results.count(201)).to eq(1)
      expect(results.count(422)).to eq(1)
      expect(invitation.reload.used?).to be true
    end
  end
end
