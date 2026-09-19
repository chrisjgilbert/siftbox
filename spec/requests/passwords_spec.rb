require "rails_helper"

RSpec.describe "Passwords" do
  it "renders the reset request form" do
    get new_password_path

    expect(response.body).to include("Forgot your password?")
  end

  it "renders the reset form for a valid token" do
    user = create(:user)
    token = user.password_reset_token

    get edit_password_path(token: token)

    expect(response.body).to include("Update your password")
  end

  it "sends a reader with an unknown token back to the request form" do
    get edit_password_path(token: "not-a-real-token")

    expect(response).to redirect_to(new_password_path)
  end

  # config.filter_parameters redacts query and body parameters, never path
  # segments. Routed as :id the token reached production STDOUT verbatim on
  # every reset, and reset mail is the only way into an account this app has
  # no sign-up flow for — so anyone who could read a log line could take it.
  # Asserts the redaction is there rather than that the token is absent. A
  # token ends in "==", which a URL carries as "%3D%3D", so `not_to
  # include(token)` held whether or not anything was filtered — the spec
  # passed with :token deleted from filter_parameters while the credential
  # went to STDOUT in full.
  it "redacts the reset token from the path the log records" do
    user = create(:user)

    get edit_password_path(token: user.password_reset_token)

    expect(request.filtered_path).to eq("/password/edit?token=[FILTERED]")
  end

  # The path cannot carry the token on this one — PATCH /password has no query
  # string and no segment — so asserting on it proves nothing. The token
  # travels in the body, and the body is what the log prints as Parameters.
  it "redacts the reset token from the parameters the log records" do
    user = create(:user)

    patch password_path, params: {
      token: user.password_reset_token,
      password: "a-long-enough-password",
      password_confirmation: "a-long-enough-password"
    }

    expect(request.filtered_parameters["token"]).to eq("[FILTERED]")
  end

  it "sets the password from a token sent in the body" do
    user = create(:user)
    token = user.password_reset_token

    patch password_path, params: {
      token: token,
      password: "a-long-enough-password",
      password_confirmation: "a-long-enough-password"
    }

    expect(user.reload.authenticate("a-long-enough-password")).to be_truthy
  end

  it "sends a reader back to the reset form when the passwords do not match" do
    user = create(:user)
    token = user.password_reset_token

    patch password_path, params: {
      token: token,
      password: "a-long-enough-password",
      password_confirmation: "a-different-password"
    }

    expect(response).to redirect_to(edit_password_path(token: token))
  end

  it "queues a reset email for a known address" do
    user = create(:user)

    expect {
      post password_path, params: { email_address: user.email_address }
    }.to have_enqueued_job.on_queue("default")
  end

  it "says nothing about whether an unknown address exists" do
    post password_path, params: { email_address: "stranger@example.com" }

    expect(response).to redirect_to(new_session_path)
  end

  # Asserts on the configuration rather than behaviour, the same way the
  # Action Mailbox ingress spec does: booting the production environment
  # in-suite is not worth it. Two failures are worth catching here. Dropping
  # the default — which .claude/rules/ruby.md would otherwise ask for — breaks
  # the image build rather than the suite, because the Dockerfile precompiles
  # assets with this environment loaded and no secrets present. And reading the
  # token back out of credentials, which this app no longer has, would send
  # reset mail authenticated by nothing. Reset mail is the only way into an
  # account with no sign-up flow, and a wrong token fails at send time, long
  # after the deploy that broke it.
  it "authenticates Postmark from the environment in production" do
    production = Rails.root.join("config/environments/production.rb").read

    expect(production).to include('ENV.fetch("POSTMARK_SMTP_TOKEN", nil)')
    expect(production).not_to include("Rails.application.credentials")
  end
end
