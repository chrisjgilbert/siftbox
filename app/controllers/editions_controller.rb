# The edition is the app: one day's briefing, and the archive of the ones
# before it. The originals live at /newsletters and are what a citation links
# out to.
class EditionsController < ApplicationController
  helper_method :badge

  def index
    @archive = Edition::Archive.new
  end

  def show
    @edition = Edition::Presenter.new(Edition.for_reading.find(params[:id]))
  end

  private

  # Chrome rather than what the page is about, so it comes through a helper
  # and leaves the action its one instance variable — see
  # .claude/rules/controllers.md. Building it on Edition::Presenter was the
  # alternative and is the thing to avoid: the edition's own presenter would
  # then know about the pen, and the notice would be reachable from the same
  # object the editor's words come out of.
  def badge
    @_badge ||= Subscriptions::Badge.new
  end
end
