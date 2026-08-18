# "This is a newsletter": the phrase set misfired, and the reader is putting
# the mail back where it belongs — the originals archive now, the next
# edition's window when it is next composed.
#
# Only mail actually in the pen may be resolved. Both endings raise on the
# other one — the state machine treats a dismissal of released mail, or a
# release of dismissed mail, as the contradiction it is — and a stale second
# tab is not worth a 500. It gets the pen, which is where the answer to what
# happened already is.
class Newsletters::ReleasesController < ApplicationController
  def create
    newsletter = Newsletter.find(params[:newsletter_id])
    newsletter.release if newsletter.held?

    redirect_to subscriptions_url
  end
end
