# Where the account's one fixed fact lives on its own page: the address a
# subscription gets pointed at. The newsletters feed already names it in the
# end-of-feed note, but that note is only there once something has arrived —
# this is the durable, always-reachable copy of it.
#
# The bookmarklet sits here for the same reason: something set up once and
# used from everywhere else afterwards.
class SettingsController < ApplicationController
  def show
    @bookmarklet = Blog::Bookmarklet.new
  end
end
