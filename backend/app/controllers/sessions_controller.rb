class SessionsController < ApplicationController
  skip_before_action :authenticate!, only: [:create]

  def create
    user = User.find_by(email: params[:email]&.downcase)
    if user&.authenticate(params[:password]) && user.active?
      user.update!(last_sign_in_at: Time.current)
      render json: { token: AuthToken.encode(user), user: serialize_user(user) }, status: :created
    else
      render json: { error: 'invalid credentials' }, status: :unauthorized
    end
  end

  def destroy
    current_user.invalidate_tokens!
    head :no_content
  end

  private

  def serialize_user(user)
    { id: user.id, email: user.email, name: user.name, role: user.role }
  end
end
