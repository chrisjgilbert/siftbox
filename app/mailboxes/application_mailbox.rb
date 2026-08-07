class ApplicationMailbox < ActionMailbox::Base
  # One dedicated address takes every subscription, so there is nothing to
  # route on. Routing by sender would mean editing a regex list every time a
  # new newsletter is subscribed to, and a miss would silently drop mail.
  routing all: :newsletters
end
