# Fetches a newsletter's hotlinked images after it is stored, rather than
# during ingest: a slow or dead image host would otherwise hold the Postmark
# webhook open, and anything raised there loses the newsletter.
class Newsletter::RemoteImagesJob < ApplicationJob
  def perform(newsletter)
    Newsletter::RemoteImages.new(newsletter).attach
  end
end
