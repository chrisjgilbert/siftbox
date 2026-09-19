# The Rails authentication generator deliberately ships no sign-up flow, so
# the first and only account is created here. A rebuilt volume gets the account
# back on its own, because `db:prepare` loads this file whenever it creates the
# database and the two variables below are part of the deployment rather than
# of the volume:
#
#   SIFTBOX_READER_EMAIL=you@example.com
#   SIFTBOX_READER_PASSWORD=...
#
# Guarded rather than fetch, against .claude/rules/ruby.md: seeds run before
# the app is reachable, so a missing variable here would abort `bin/setup` and
# the first production container boot rather than surface anywhere useful.
email_address = ENV["SIFTBOX_READER_EMAIL"]
password = ENV["SIFTBOX_READER_PASSWORD"]

if email_address.blank? || password.blank?
  puts "No reader account created. Set SIFTBOX_READER_EMAIL and " \
       "SIFTBOX_READER_PASSWORD, then run bin/rails db:seed."
else
  # Create, never update. Seeds run again on any later db:prepare, and the
  # reader may have changed their password through the reset flow since.
  User.find_or_create_by!(email_address: email_address) do |user|
    user.password = password
  end
end
