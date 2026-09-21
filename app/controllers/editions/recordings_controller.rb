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

  def show
    blob = playable
    return head :not_found if blob.nil?

    # An hour rather than a year, which is what an immutable file would earn.
    # A recording that failed and was asked for again replaces the audio at this
    # same address, so a long cache would serve the reader the silence they
    # complained about. An hour covers one listening session's range requests.
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

  # The recording reached through its edition rather than found by its own id,
  # so an address that names one edition can never answer with another's audio.
  def recording
    edition.recording
  end

  # nil for every reason the page should not be offering audio: no recording,
  # one still being made, one that failed, or one whose blob is labelled as
  # something this controller does not serve. The label is this app's own rather
  # than a stranger's, so the last is a floor rather than a defence — it is here
  # so the thing that writes the type and the thing that serves it cannot drift
  # apart in silence.
  def playable
    found = recording
    return if found.nil? || !found.ready?

    blob = found.audio.blob
    blob if blob.content_type == Edition::Recording::AUDIO_TYPE
  end

  def serve(blob)
    range = request.headers["Range"]
    return send_whole(blob) if range.blank?

    send_range(blob, range)
  end

  # Accept-Ranges on the first answer is what tells a player it may seek at all.
  def send_whole(blob)
    response.headers["Accept-Ranges"] = "bytes"

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
    response.headers["Accept-Ranges"] = "bytes"
    response.headers["Content-Range"] = "bytes */#{blob.byte_size}"

    head :range_not_satisfiable
  end

  def send_chunk(blob, range)
    response.headers["Accept-Ranges"] = "bytes"
    response.headers["Content-Range"] = "bytes #{range.begin}-#{range.end}/#{blob.byte_size}"

    send_data blob.download_chunk(range), type: blob.content_type,
      disposition: :inline, status: :partial_content
  end
end
