# Someone who wants an address once siftbox opens.
#
# The landing page is the only public write path in this app, so what this
# class does not do matters as much as what it does: it sends no mail — the
# copy promises exactly one message, and a confirmation would break that
# promise on day one — and it never tells a visitor whether an address is
# already on the list.
class WaitlistSignup < ApplicationRecord
  # Not a column. A real visitor never sees the field, so anything in it came
  # from something filling every input on the page.
  attr_accessor :website

  validates :email, format: { with: URI::MailTo::EMAIL_REGEXP }, presence: true

  before_validation :normalise_email

  # A duplicate is a success. The unique index raises rather than a
  # validation failing, because a uniqueness validation would have to report
  # the clash, and reporting it answers a question about someone else's
  # address.
  def join
    return true if honeypot_filled?
    return false unless valid?

    save
  rescue ActiveRecord::RecordNotUnique
    true
  end

  private

  # Nothing is written and nothing is said. A 422 here would tell a bot
  # exactly which field caught it.
  def honeypot_filled?
    website.present?
  end

  def normalise_email
    self.email = email.to_s.strip.downcase
  end
end
