# The images a newsletter hotlinks, stored at ingest the way
# Newsletter::InlineImages stores the cid: ones — so the archive keeps its
# images when the sender's CDN forgets them, and opening a newsletter tells
# the sender nothing. Not built yet: the specs in
# spec/models/newsletter/remote_images_spec.rb name the behaviour, and this
# skeleton only keeps the suite loading while they are red.
class Newsletter::RemoteImages
  def initialize(newsletter, download: nil)
    @newsletter = newsletter
    @download = download
  end

  def attach
    raise NotImplementedError
  end
end
