class User < ApplicationRecord
  has_secure_password
  has_many :sessions, dependent: :destroy

  normalizes :email_address, with: ->(e) { e.strip.downcase }

  # A reset is only a recovery if it also ends the sessions it was meant to
  # take back. The session cookie is permanent and nothing in the UI can
  # revoke one, so a reset that leaves them alive lets a stolen cookie outlive
  # the password it was taken with.
  def reset_password(attributes)
    return false unless update(attributes)

    sessions.destroy_all
    true
  end
end
