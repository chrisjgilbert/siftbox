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

RSpec.configure do |config|
  config.include AuthenticationHelper, type: :request
end
