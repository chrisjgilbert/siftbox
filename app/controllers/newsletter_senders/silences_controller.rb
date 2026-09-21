# The way back, from the roster.
#
# Unmuting takes effect from that moment onwards. The edition window starts at
# the watermark, which moved every morning of the silence — a morning whose
# only arrivals were muted reads as empty and the job records an
# Edition::Gap — so the sender rejoins the next edition rather than arriving
# with everything they wrote during it.
class NewsletterSenders::SilencesController < ApplicationController
  def destroy
    Newsletter::Sender.find(params[:newsletter_sender_id]).unsilence

    redirect_to subscriptions_url
  end
end
