# Fetches a newsletter's hotlinked images after it is stored, rather than
# during ingest: a slow or dead image host would otherwise hold the Postmark
# webhook open, and anything raised there loses the newsletter.
class Newsletter::RemoteImagesJob < ApplicationJob
  # A newsletter deleted between ingest and the fetch has no images left to
  # want. Without this the job retries and then sits in the failed queue
  # forever over a record nobody kept.
  discard_on ActiveJob::DeserializationError

  # Captured again after the fetch, not only at ingest: attach rewrites every
  # image it stored to a path this app serves, and the lead image read before
  # that still points at the sender's CDN. Left there, the feed would hotlink
  # a thumbnail per row on every load — the one request this whole class
  # exists to stop making. Outside #attach because a newsletter whose images
  # all failed to download still has a lead worth reading.
  def perform(newsletter)
    Newsletter::RemoteImages.new(newsletter).attach
    newsletter.capture_lead_image
  end
end
