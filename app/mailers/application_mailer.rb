class ApplicationMailer < ActionMailer::Base
  default from: ENV.fetch("SIFTBOX_MAIL_FROM", "siftbox@localhost")
  layout "mailer"
end
