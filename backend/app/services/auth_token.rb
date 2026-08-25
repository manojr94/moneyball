class AuthToken
  EXPIRY = 24.hours
  ALGORITHM = 'HS256'.freeze

  class InvalidTokenError < StandardError; end

  def self.encode(user)
    payload = {
      user_id: user.id,
      token_version: user.token_version,
      exp: EXPIRY.from_now.to_i
    }
    JWT.encode(payload, secret, ALGORITHM)
  end

  def self.decode(token)
    payload = JWT.decode(token, secret, true, algorithms: [ALGORITHM]).first
    payload.symbolize_keys
  rescue JWT::DecodeError => e
    raise InvalidTokenError, e.message
  end

  def self.secret
    Rails.application.secret_key_base
  end
  private_class_method :secret
end
