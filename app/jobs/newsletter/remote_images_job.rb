# Fetches a newsletter's hotlinked images off the ingest path, so a slow or
# dead image host cannot slow the Postmark webhook or lose the newsletter.
# Not built yet: see spec/jobs/newsletter/remote_images_job_spec.rb.
class Newsletter::RemoteImagesJob < ApplicationJob
  def perform(_newsletter)
    raise NotImplementedError
  end
end
