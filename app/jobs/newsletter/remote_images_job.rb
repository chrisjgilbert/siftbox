# Fetches a newsletter's hotlinked images after it is stored, rather than
# during ingest: a slow or dead image host would otherwise hold the Postmark
# webhook open, and anything raised there loses the newsletter.
class Newsletter::RemoteImagesJob < ApplicationJob
  # A newsletter deleted between ingest and the fetch has no images left to
  # want. Without this the job retries and then sits in the failed queue
  # forever over a record nobody kept.
  discard_on ActiveJob::DeserializationError

  def perform(newsletter)
    Newsletter::RemoteImages.new(newsletter).attach
  end
end
