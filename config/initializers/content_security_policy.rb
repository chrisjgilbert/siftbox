# Be sure to restart your server when you modify this file.

# The reader view renders sender-supplied HTML inline, so the allowlist in
# Newsletter::Body is the thing standing between a newsletter and the page.
# This policy is the second line: if the sanitizer ever regresses — a Loofah
# CVE, or a tag added to the allowlist without thinking it through — a script
# still has nowhere to run.
Rails.application.configure do
  config.content_security_policy do |policy|
    policy.default_src :self
    policy.object_src  :none
    policy.base_uri    :none
    policy.frame_src   :self
    policy.script_src  :self
    policy.style_src   :self, "https://fonts.googleapis.com"
    policy.font_src    :self, "https://fonts.gstatic.com"

    # Newsletter images are hotlinked to the sender's CDN, and inline ones
    # are served from Active Storage.
    policy.img_src     :self, :https, :data
    policy.form_action :self
    policy.frame_ancestors :none
  end

  # Lets the importmap's inline script and Turbo's injected progress-bar
  # style run, without opening either directive to every inline block.
  #
  # Not the session id the Rails comment suggests: it is nil until something
  # writes to the session, which renders an empty `'nonce-'` and blocks the
  # importmap — taking Turbo down with it. Rails memoises this per request,
  # so one value covers the meta tag and every tag that reads it.
  config.content_security_policy_nonce_generator = ->(_request) { SecureRandom.base64(16) }
  config.content_security_policy_nonce_directives = %w[script-src style-src]
end
