module AuthenticationHelper
  PASSWORD = "a-long-enough-password".freeze

  def sign_in(user = create(:user, password: PASSWORD))
    post session_path, params: {
      email_address: user.email_address,
      password: PASSWORD
    }
    user
  end
end

RSpec.configure do |config|
  config.include AuthenticationHelper, type: :request
end
