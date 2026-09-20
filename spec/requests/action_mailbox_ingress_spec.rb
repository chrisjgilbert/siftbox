require "rails_helper"

# The path Postmark posts to. Losing any part of it — the route, the ingress
# setting, the RawEmail parameter, the ingress password — is silent and total:
# the webhook fails, Postmark eventually stops retrying, and the newsletters
# are gone with nothing logged.
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
  #
  # Action Mailbox still reads action_mailbox.ingress_password first and only
  # falls back to RAILS_INBOUND_EMAIL_PASSWORD, but there are no credentials to
  # hold one any more, so the fallback is the whole mechanism and the variable
  # is what decides in production too. It is read per request, so a value set
  # for the example's duration is what the controller authenticates against.
  # Set and put back rather than stubbed, through
  # spec/support/environment_helper.rb: ENV is process-wide.
  def armed(&delivery)
    ActionMailbox.ingress = :postmark

    with_environment("RAILS_INBOUND_EMAIL_PASSWORD" => "ingress-password") do
      perform_enqueued_jobs(&delivery)
    end
  ensure
    ActionMailbox.ingress = nil
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
