require "rails_helper"

# The path Postmark posts to. Losing any part of it — the route, the ingress
# setting, the RawEmail parameter, the credentials — is silent and total: the
# webhook fails, Postmark eventually stops retrying, and the newsletters are
# gone with nothing logged.
RSpec.describe "Action Mailbox ingress" do
  include ActiveJob::TestHelper

  def postmark_source
    "From: Ruby Weekly <peter@rubyweekly.com>\n" \
    "To: news@example.com\nSubject: Issue 742\n\n<p>Morning</p>"
  end

  def credentials
    ActionController::HttpAuthentication::Basic.encode_credentials(
      "actionmailbox", "ingress-password"
    )
  end

  # Arms the ingress for one example. It is production-only in config, so
  # this is the only way to exercise a real delivery.
  #
  # The ingress stores the message and enqueues routing rather than routing
  # inline, so the job has to run for a Newsletter to exist.
  def armed(&delivery)
    ActionMailbox.ingress = :postmark
    stub_ingress_password("ingress-password")
    perform_enqueued_jobs(&delivery)
  ensure
    ActionMailbox.ingress = nil
  end

  # Action Mailbox reads the credential first and only falls back to
  # RAILS_INBOUND_EMAIL_PASSWORD, so the credential is what decides. Stubbing
  # the fallback instead passes locally and authenticates nothing in
  # production.
  def stub_ingress_password(password)
    credentials = Rails.application.credentials

    allow(credentials).to receive(:dig).and_call_original
    allow(credentials)
      .to receive(:dig)
      .with(:action_mailbox, :ingress_password)
      .and_return(password)
  end

  it "turns an authenticated Postmark delivery into a newsletter" do
    armed do
      post rails_postmark_inbound_emails_path,
        params: { RawEmail: postmark_source },
        headers: { "HTTP_AUTHORIZATION" => credentials }
    end

    expect(Newsletter.count).to eq(1)
  end

  it "accepts that delivery" do
    armed do
      post rails_postmark_inbound_emails_path,
        params: { RawEmail: postmark_source },
        headers: { "HTTP_AUTHORIZATION" => credentials }
    end

    expect(response).to have_http_status(:no_content)
  end

  it "refuses a delivery carrying no credentials" do
    armed do
      post rails_postmark_inbound_emails_path, params: { RawEmail: postmark_source }
    end

    expect(response).to have_http_status(:unauthorized)
  end

  it "answers 404 where the ingress is deliberately not armed" do
    post rails_postmark_inbound_emails_path, params: { RawEmail: postmark_source }

    expect(response).to have_http_status(:not_found)
  end

  # Asserts on the configuration rather than behaviour: booting the production
  # environment in-suite is not worth it, and the failure worth catching is
  # the line being deleted or typo'd. The trailing newline is what rejects a
  # near-miss like `:postmarks`.
  it "is armed for Postmark in production" do
    production = Rails.root.join("config/environments/production.rb").read

    expect(production).to include("config.action_mailbox.ingress = :postmark\n")
  end
end
