# The Rails authentication generator deliberately ships no sign-up flow, so
# the first and only account is created here.
#
#   NEWSBOX_EMAIL=you@example.com NEWSBOX_PASSWORD=... bin/rails db:seed
User.find_or_create_by!(email_address: ENV.fetch("NEWSBOX_EMAIL")) do |user|
  user.password = ENV.fetch("NEWSBOX_PASSWORD")
end
