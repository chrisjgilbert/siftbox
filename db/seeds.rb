# The Rails authentication generator deliberately ships no sign-up flow, so
# the first and only account is created here. It comes from credentials rather
# than the environment so that a rebuilt volume gets the account back on its
# own — `db:prepare` loads this file whenever it creates the database.
#
#   bin/rails credentials:edit
#
#   reader:
#     email_address: you@example.com
#     password: ...
#
# Guarded rather than fetch, against .claude/rules/ruby.md: seeds run before
# the app is reachable, so a missing key here would abort `bin/setup` and the
# first production container boot rather than surface anywhere useful.
reader = Rails.application.credentials.reader

if reader.blank? || reader[:email_address].blank? || reader[:password].blank?
  puts "No reader account created. Add reader.email_address and reader.password " \
       "with bin/rails credentials:edit, then run bin/rails db:seed."
else
  # Create, never update. Seeds run again on any later db:prepare, and the
  # reader may have changed their password through the reset flow since.
  User.find_or_create_by!(email_address: reader[:email_address]) do |user|
    user.password = reader[:password]
  end
end
