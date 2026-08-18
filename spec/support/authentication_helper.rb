module AuthenticationHelper
  # Asserts the sign-in worked. Without this a broken session leaves every
  # `not_to include(...)` in the request specs passing against an empty
  # redirect body.
  def sign_in(user = create(:user))
    post session_path, params: {
      email_address: user.email_address,
      password: user.password
    }
    raise "sign_in failed: #{response.status} to #{response.location}" unless
      response.redirect? && !response.location.to_s.include?(new_session_path)

    user
  end
end

# The same gate from the outside. A system spec has no request object to post
# through, so it fills the form in, which is also the one place the sign-in
# page itself gets exercised end to end.
module FormAuthenticationHelper
  def sign_in_through_the_form(user = create(:user))
    visit new_session_path
    fill_in I18n.t("sessions.new.email"), with: user.email_address
    fill_in I18n.t("sessions.new.password"), with: user.password
    click_button I18n.t("sessions.new.submit")

    user
  end
end

RSpec.configure do |config|
  config.include AuthenticationHelper, type: :request
  config.include FormAuthenticationHelper, type: :system
end
