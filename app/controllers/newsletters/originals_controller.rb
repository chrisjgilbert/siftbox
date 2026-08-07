# The escape hatch for newsletters that lose too much to the allowlist: the
# chrome around a sandboxed iframe. The iframe loads Newsletters::SourcesController.
class Newsletters::OriginalsController < ApplicationController
  def show
    @newsletter = Newsletter.find(params[:newsletter_id])
  end
end
