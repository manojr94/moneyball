class ApplicationController < ActionController::API
  before_action :authenticate!

  attr_reader :current_user

  rescue_from NotAuthorizedError do
    render json: { error: 'forbidden' }, status: :forbidden
  end

  private

  def authenticate!
    token = bearer_token
    raise AuthToken::InvalidTokenError, 'missing token' unless token

    payload = AuthToken.decode(token)
    @current_user = verified_user(payload)
  rescue AuthToken::InvalidTokenError
    render json: { error: 'invalid or expired token' }, status: :unauthorized
  end

  def verified_user(payload)
    user = User.find_by(id: payload[:user_id])
    raise AuthToken::InvalidTokenError, 'invalid token' unless user
    raise AuthToken::InvalidTokenError, 'token has been revoked' if user.token_version != payload[:token_version]
    raise AuthToken::InvalidTokenError, 'account is deactivated' unless user.active?

    user
  end

  def authorize!(action, record = nil, policy_class: ApplicationPolicy)
    raise NotAuthorizedError unless policy_class.new(current_user, record).public_send(:"#{action}?")
  end

  def bearer_token
    header = request.headers['Authorization']
    header&.split(' ', 2)&.last if header&.start_with?('Bearer ')
  end
end
