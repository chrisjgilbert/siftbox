# Fetches a stored body's hotlinked images afterwards rather than during
# ingest. On the mail side a slow or dead image host would otherwise hold the
# Postmark webhook open, and anything raised there loses the newsletter; on
# the feed side it would hold the poll open, and the roster behind it.
class RemoteImagesJob < ApplicationJob
  # A record deleted between ingest and the fetch has no images left to want.
  # Without this the job retries and then sits in the failed queue forever
  # over a record nobody kept.
  discard_on ActiveJob::DeserializationError

  # Captured again after the fetch, not only at ingest: attach rewrites every
  # image it stored to a path this app serves, and the lead image read before
  # that still points at the publisher's CDN. Left there, the archive would
  # hotlink a thumbnail per row on every load — the one request this whole
  # class exists to stop making. Outside #attach because a record whose images
  # all failed to download still has a lead worth reading.
  def perform(record)
    RemoteImages.new(record).attach
    record.capture_lead_image
  end
end
