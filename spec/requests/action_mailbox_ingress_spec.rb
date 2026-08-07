require "rails_helper"

# The ingress is production-only, so no request spec can exercise a real
# delivery: outside production ActionMailbox.ingress is nil and the endpoint
# answers 404 by design. These pin the two halves of that arrangement,
# because losing the configuration is silent and total — every Postmark
# webhook 404s, Postmark retries for about six hours, and the newsletters are
# gone with nothing logged.
RSpec.describe "Action Mailbox ingress" do
  it "answers 404 outside production, where it is deliberately not armed" do
    post "/rails/action_mailbox/postmark/inbound_emails",
      params: { RawEmail: "From: a@b.com\nSubject: s\n\nhi" }

    expect(response).to have_http_status(:not_found)
  end

  # Asserts on the configuration rather than on behaviour: booting the
  # production environment inside the suite is not worth it, and deletion or
  # a typo here is the failure worth catching.
  #
  # Anchored to the end of the line rather than an `include`, which a typo
  # like `:postmarks` would satisfy as a substring.
  it "is armed for Postmark in production" do
    production = Rails.root.join("config/environments/production.rb").read

    expect(production).to match(/^\s*config\.action_mailbox\.ingress = :postmark$/)
  end
end
