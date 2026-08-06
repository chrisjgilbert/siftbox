class ApplicationMailer < ActionMailer::Base
  default from: ENV.fetch("NEWSBOX_MAIL_FROM", "newsbox@localhost")
  layout "mailer"
end
