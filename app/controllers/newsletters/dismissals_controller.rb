# Done with a held confirmation. The app cannot see the reader click the
# sender's confirm button — the original renders in a sandboxed frame with an
# opaque origin and no scripts — so this request is the only evidence there is
# that the hold is finished with. Nothing infers it; see
# Newsletters::OriginalsController's view for why nothing ever should.
class Newsletters::DismissalsController < ApplicationController
  def create
    newsletter = Newsletter.find(params[:newsletter_id])
    newsletter.dismiss if newsletter.held?

    redirect_to subscriptions_url
  end
end
