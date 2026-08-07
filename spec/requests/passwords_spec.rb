require "rails_helper"

RSpec.describe "Passwords" do
  it "renders the reset request form" do
    get new_password_path

    expect(response.body).to include("Forgot your password?")
  end

  it "renders the reset form for a valid token" do
    user = create(:user)
    token = user.password_reset_token

    get edit_password_path(token)

    expect(response.body).to include("Update your password")
  end

  it "sends a reader with an unknown token back to the request form" do
    get edit_password_path("not-a-real-token")

    expect(response).to redirect_to(new_password_path)
  end

  it "queues a reset email for a known address" do
    user = create(:user)

    expect {
      post passwords_path, params: { email_address: user.email_address }
    }.to have_enqueued_job.on_queue("default")
  end

  it "says nothing about whether an unknown address exists" do
    post passwords_path, params: { email_address: "stranger@example.com" }

    expect(response).to redirect_to(new_session_path)
  end

  # Asserts on the configuration rather than behaviour, the same way the
  # Action Mailbox ingress spec does: booting the production environment
  # in-suite is not worth it, and the failure worth catching is someone
  # putting the token back in ENV. Reset mail is the only way into an account
  # with no sign-up flow, and a wrong token fails at send time, long after the
  # deploy that broke it.
  it "authenticates Postmark from credentials in production" do
    production = Rails.root.join("config/environments/production.rb").read

    expect(production).to include("credentials.dig(:postmark, :smtp_token)")
    expect(production).not_to include("POSTMARK_SMTP_TOKEN")
  end
end
