class PasswordsController < ApplicationController
  allow_unauthenticated_access
  # The only unauthenticated endpoint in this app that sends mail, and it
  # sends through the same Postmark account the newsletters arrive on — so an
  # unthrottled loop here burns the sender reputation the whole product runs
  # on, not just password reset.
  rate_limit to: 5, within: 3.minutes, only: :create,
    with: -> { redirect_to new_password_url, alert: "Try again later." }
  before_action :set_user_by_token, only: %i[ edit update ]

  def new
  end

  def create
    if user = User.find_by(email_address: params[:email_address])
      PasswordsMailer.reset(user).deliver_later
    end

    redirect_to new_session_url, notice: "Password reset instructions sent (if user with that email address exists)."
  end

  def edit
  end

  def update
    if @user.reset_password(password_params)
      redirect_to new_session_url, notice: "Password has been reset."
    else
      redirect_to edit_password_url(token: params[:token]), alert: "Passwords did not match."
    end
  end

  private
    def password_params
      params.permit(:password, :password_confirmation)
    end

    def set_user_by_token
      @user = User.find_by_password_reset_token!(params[:token])
    rescue ActiveSupport::MessageVerifier::InvalidSignature
      redirect_to new_password_url, alert: "Password reset link is invalid or has expired."
    end
end
