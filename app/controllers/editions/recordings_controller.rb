# Asking to hear an edition, and the audio that comes back.
#
# The audio is served from here rather than from Active Storage's own blob
# routes, for the reason StoredImages gives about the images: those routes
# inherit from ActionController::Base rather than from ApplicationController, so
# they sit outside the authentication gate and their signed ids never expire — a
# permanent public URL for every recording in a private archive.
#
# What is not shared with StoredImages is the important part. That concern
# answers with a bare send_data, which is fine for an image and not enough for
# audio: a media element seeks by asking for byte ranges, and Safari will not
# play a source at all from a server that does not offer them. So the Range
# branch below, which is ActiveStorage::Blobs::ProxyController's shape without
# ActiveStorage::Streaming — that concern pulls in ActionController::Live, which
# runs every action in this controller on another thread, and Current.session is
# thread-local. A few megabytes needs no streaming to serve whole.
class Editions::RecordingsController < ApplicationController
  # The only create in this app that spends somebody else's money per request,
  # and until now the only one with no limit on it — BlogsController's own
  # comment says every other create is limited the same way. Edition::Recording
  # .start already refuses to start a second job while one is running or an
  # edition already plays, so reaching this needs a loop against distinct
  # editions; five a minute is more listening than a reader does in a morning
  # and bounds what a held-open tab can spend.
  rate_limit to: 5, within: 1.minute, only: :create,
    with: -> { redirect_to editions_url, alert: I18n.t("editions.recording.too_many") }

  def create
    Edition::Recording.start(edition)

    redirect_to edition_url(edition)
  end

  # The validator is not decoration, and it is the part of
  # ActiveStorage::Blobs::ProxyController's shape that did not come across the
  # first time. Without one, Rack::ETag — which is in this app's middleware —
  # digests the whole response to make its own, so every full answer read a few
  # megabytes off disk and then hashed them again, and a conditional request
  # still paid for both before answering 304. The blob's checksum is already on
  # the row this action loads, so stating it costs nothing and stops both.
  #
  # It is also what lets the cache window stay short without being expensive: a
  # recording that failed and was asked for again replaces the audio at this
  # same address, so the reader has to be able to find that out — and now
  # finding out is a 304 rather than a download.
  def show
    blob = playable
    return head :not_found if blob.nil?
    return unless stale?(strong_etag: blob.checksum, last_modified: blob.created_at,
      public: false)

    expires_in 1.hour, public: false
    serve(blob)
  end

  private

  # Only the id is needed, and an editions row carries raw_response — the
  # model's whole answer to the morning's prompt, which runs to tens of
  # kilobytes.
  #
  # Memoised so create can redirect to the record rather than back to
  # params[:edition_id] without paying for a second read. Redirecting to the
  # record matters because find typecasts: "7abc" finds edition 7, and the raw
  # parameter would send the reader to /editions/7abc, a URL that only resolves
  # because the next request typecasts it too.
  def edition
    @_edition ||= Edition.select(:id).find(params[:edition_id])
  end

  # Keyed on the edition id from the path rather than reached through a loaded
  # Edition, which answers the same question — a recording belongs to one
  # edition, so an address naming one can never answer with another's audio —
  # without reading a row this action then never touches. show runs on every
  # seek, so the read it does not need is the one worth not doing.
  def recording
    Edition::Recording.find_by(edition_id: params[:edition_id])
  end

  # nil for every reason the page should not be offering audio: no recording at
  # all, one still being made, or one that failed.
  def playable
    found = recording
    return if found.nil? || !found.ready?

    found.audio.blob
  end

  # Accept-Ranges on every answer, which is what tells a player it may seek at
  # all. Set once here rather than in each of the three ways out below, all of
  # which want it.
  def serve(blob)
    response.headers["Accept-Ranges"] = "bytes"
    range = request.headers["Range"]
    return send_whole(blob) if range.blank?

    send_range(blob, range)
  end

  def send_whole(blob)
    send_data blob.download, type: blob.content_type, disposition: :inline
  end

  # One range is answered as a range; anything else this will not build is
  # answered with the whole file rather than refused. RFC 9110 lets a server
  # ignore a Range header and reply 200 with the whole entity, and every client
  # accepts that — where a 416 leaves a player with no audio at all. So a
  # header Rack cannot read as a byte range (nil) and a multipart request
  # (more than one range, which no media player sends) both fall through to
  # the whole file.
  #
  # An empty list is the one case that is genuinely unsatisfiable — the range
  # starts past the end — and that is the 416 the spec reserves for it.
  def send_range(blob, header)
    ranges = Rack::Utils.get_byte_ranges(header, blob.byte_size)
    return send_whole(blob) if ranges.nil? || ranges.length > 1
    return unsatisfiable(blob) if ranges.empty?

    send_chunk(blob, ranges.first)
  end

  # Content-Range in its unsatisfied form, which is what RFC 9110 §15.5.17 asks
  # a 416 to carry and the only thing that lets a client correct itself: a
  # player holding a stale duration — which the retry path makes possible,
  # since a second recording can be shorter than the one it replaced at this
  # same address — has nothing to re-request from without the real length.
  def unsatisfiable(blob)
    response.headers["Content-Range"] = "bytes */#{blob.byte_size}"

    head :range_not_satisfiable
  end

  def send_chunk(blob, range)
    response.headers["Content-Range"] = "bytes #{range.begin}-#{range.end}/#{blob.byte_size}"

    send_data blob.download_chunk(range), type: blob.content_type,
      disposition: :inline, status: :partial_content
  end
end
