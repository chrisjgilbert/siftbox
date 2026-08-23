# Be sure to restart your server when you modify this file.

# Configure parameters to be partially matched (e.g. passw matches password) and filtered from the log file.
# Use this to limit dissemination of sensitive information.
# See the ActiveSupport::ParameterFilter documentation for supported notations and behaviors.
# feed_url is here because a private feed address is a bearer credential: a
# Feedbin, Substack or GitHub notification feed carries its secret in the URL
# itself, as a query parameter or as userinfo. Filtering matches on the
# parameter name rather than the value, so the whole address would otherwise
# reach the production log at info level.
Rails.application.config.filter_parameters += [
  :passw, :email, :secret, :token, :_key, :crypt, :salt, :certificate, :otp, :ssn, :cvv,
  :cvc, :feed_url
]
