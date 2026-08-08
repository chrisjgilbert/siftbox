require "rails_helper"

RSpec.describe PasswordsMailer do
  # Both templates build the reset URL themselves, and deliver_later means
  # nothing else in the suite renders either one — a route change that made
  # edit_password_url raise would blow up inside the job, after the controller
  # had already told the reader instructions were sent, with the suite green.
  # This is the only way into an account: the app has no sign-up flow.
  it "links the reader to a reset page that resolves" do
    user = create(:user)

    mail = PasswordsMailer.reset(user)

    expect(Rails.application.routes.recognize_path(URI.parse(link_in(mail)).path))
      .to eq(controller: "passwords", action: "edit")
  end

  # Asserted by reading the token back rather than by comparing it to a fresh
  # one: password_reset_token signs the time into every call, so two of them
  # are never equal even for the same reader. A link that resolves but carries
  # nothing usable is the same outage as one that 404s.
  it "sends a token the app reads back as the same reader" do
    user = create(:user)

    mail = PasswordsMailer.reset(user)

    expect(User.find_by_password_reset_token!(token_in(mail))).to eq(user)
  end

  it "renders the plain text part with the same link" do
    user = create(:user)

    mail = PasswordsMailer.reset(user)

    expect(mail.text_part.decoded).to include("/password/edit?token=")
  end

  def link_in(mail)
    mail.html_part.decoded[/href="([^"]+)"/, 1]
  end

  def token_in(mail)
    URI.decode_www_form(URI.parse(link_in(mail)).query).to_h.fetch("token")
  end
end
