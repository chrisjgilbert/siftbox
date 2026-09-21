# Muting from the issue in front of the reader. What it mutes is the sender,
# not the issue: the decision is about who writes, so it reaches the back
# catalogue and whatever arrives next alike.
#
# Nothing is hidden. The issue keeps its place in the originals archive and
# the sender keeps writing; what stops is the sender reaching an edition. See
# Edition::Window, which is the one place a silence applies.
class Newsletters::SilencesController < ApplicationController
  def create
    Newsletter::Sender.muting(Newsletter.find(params[:newsletter_id]))

    redirect_to subscriptions_url
  end
end
