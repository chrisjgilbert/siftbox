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
    # :token is permitted and then dropped. It arrives in the body now that it
    # has moved out of the path, so leaving it unpermitted logged "Unpermitted
    # parameter: :token" on every reset and would raise anywhere
    # action_on_unpermitted_parameters is :raise. It addresses the reader
    # rather than describing the password, so it does not belong in the
    # attributes either.
    #
    # `_method` and `authenticity_token` still report unpermitted here, as
    # they have since before the token moved: this permits at the top level,
    # where a form's own fields sit alongside the model's. Scoping the form
    # would silence them, and is a bigger change than a log line is worth.
    def password_params
      params.permit(:token, :password, :password_confirmation).except(:token)
    end

    def set_user_by_token
      @user = User.find_by_password_reset_token!(params[:token])
    rescue ActiveSupport::MessageVerifier::InvalidSignature
      redirect_to new_password_url, alert: "Password reset link is invalid or has expired."
    end
end
