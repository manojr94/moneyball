class RegistrationsController < ApplicationController
  skip_before_action :authenticate!

  def create
    outcome = perform_signup
    case outcome[:status]
    when :created        then render json: outcome[:body], status: :created
    when :invalid_token  then render_invalid_token
    when :validation_error
      render json: { errors: outcome[:errors] }, status: :unprocessable_content
    end
  end

  private

  # rubocop:disable Metrics/MethodLength
  def perform_signup
    outcome = { status: nil }
    user = build_user

    ActiveRecord::Base.transaction do
      invitation = Invitation.unused.lock.find_by(token: params[:token])
      unless invitation
        outcome[:status] = :invalid_token
        raise ActiveRecord::Rollback
      end

      if user.save
        invitation.use!
        outcome = { status: :created, body: signup_body(user) }
      else
        outcome = { status: :validation_error, errors: user.errors.full_messages }
        raise ActiveRecord::Rollback
      end
    end

    outcome
  end
  # rubocop:enable Metrics/MethodLength

  def build_user
    User.new(name: params[:name], email: params[:email],
             password: params[:password], role: 'hr_admin')
  end

  def signup_body(user)
    { token: AuthToken.encode(user),
      user: { id: user.id, name: user.name, email: user.email, role: user.role } }
  end

  def render_invalid_token
    render json: { error: 'This invitation link is invalid or has already been used.' },
           status: :unprocessable_content
  end
end
