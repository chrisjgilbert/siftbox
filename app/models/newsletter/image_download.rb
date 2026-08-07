# One hotlinked image, fetched by the server at ingest so the reader's
# browser never has to. Not built yet: the specs in
# spec/models/newsletter/image_download_spec.rb name the behaviour — most of
# it the server-side request forgery checks — and this skeleton only keeps
# the suite loading while they are red.
class Newsletter::ImageDownload
  MAX_BYTES = 5.megabytes
  MAX_REDIRECTS = 3

  def initialize(url, resolver: nil)
    @url = url
    @resolver = resolver
  end

  def image
    raise NotImplementedError
  end
end
