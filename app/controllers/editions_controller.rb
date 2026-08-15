# The edition is the app: one day's briefing, and the archive of the ones
# before it. The originals live at /newsletters and are what a citation links
# out to.
class EditionsController < ApplicationController
  def index
    @archive = Edition::Archive.new
  end

  def show
    @edition = Edition::Presenter.new(Edition.find(params[:id]))
  end
end
