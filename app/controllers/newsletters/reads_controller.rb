# Marking a newsletter unread again. A nested resource rather than a custom
# verb on NewslettersController — see .claude/rules/controllers.md on routes.
class Newsletters::ReadsController < ApplicationController
  def destroy
    newsletter = Newsletter.find(params[:newsletter_id])
    newsletter.mark_unread

    redirect_to newsletters_path
  end
end
