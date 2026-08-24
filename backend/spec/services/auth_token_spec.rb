require 'rails_helper'

RSpec.describe AuthToken do
  let(:user) { create(:user) }

  describe '.encode / .decode round-trip' do
    it 'encodes a token that decodes back to the user' do
      token = described_class.encode(user)
      payload = described_class.decode(token)
      expect(payload[:user_id]).to eq(user.id)
      expect(payload[:token_version]).to eq(user.token_version)
    end
  end

  describe '.decode' do
    it 'raises InvalidTokenError for a malformed token' do
      expect { described_class.decode('not.a.token') }
        .to raise_error(described_class::InvalidTokenError)
    end

    it 'raises InvalidTokenError for an expired token' do
      token = travel_to(25.hours.ago) { described_class.encode(user) }
      expect { described_class.decode(token) }.to raise_error(described_class::InvalidTokenError)
    end

    it 'raises InvalidTokenError for a tampered token' do
      header, payload, _sig = described_class.encode(user).split('.')
      tampered = [header, payload, 'invalidsignature'].join('.')
      expect { described_class.decode(tampered) }.to raise_error(described_class::InvalidTokenError)
    end
  end

  describe 'token_version in payload' do
    it 'carries the token_version at encode time' do
      user.invalidate_tokens!
      token = described_class.encode(user)
      payload = described_class.decode(token)
      expect(payload[:token_version]).to eq(user.reload.token_version)
    end

    it 'an older token carries the pre-invalidation token_version' do
      old_token = described_class.encode(user)
      user.invalidate_tokens!
      old_payload = described_class.decode(old_token)
      expect(old_payload[:token_version]).not_to eq(user.reload.token_version)
    end
  end
end
