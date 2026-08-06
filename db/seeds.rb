# The Rails authentication generator deliberately ships no sign-up flow, so
# the first and only account is created here.
#
#   NEWSBOX_EMAIL=you@example.com NEWSBOX_PASSWORD=... bin/rails db:seed
#
# Guarded rather than ENV.fetch, against .claude/rules/ruby.md: `db:prepare`
# loads seeds whenever it creates the database, so a missing key here aborts
# `bin/setup` and the first production container boot before either reaches
# the app.
email = ENV["NEWSBOX_EMAIL"]
password = ENV["NEWSBOX_PASSWORD"]

if email.blank? || password.blank?
  puts "No reader account created. Set NEWSBOX_EMAIL and NEWSBOX_PASSWORD, " \
       "then run bin/rails db:seed."
else
  User.find_or_create_by!(email_address: email) { |user| user.password = password }
end
