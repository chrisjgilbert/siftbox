require "net/http"

# One image a newsletter hotlinks, fetched by this server at ingest so the
# reader's browser never asks the sender for it.
#
# Where the request may go is Destination's question, and it is asked again
# on every redirect. What is left here is the fetch itself: a ceiling on
# redirects, a cap on bytes, and only the image types the reader renders.
class Newsletter::ImageDownload
  MAX_BYTES = 5.megabytes
  MAX_REDIRECTS = 3
  TIMEOUT = 5

  # Fetching arbitrary URLs off the public internet fails in a dozen
  # ordinary ways, so these are not the exceptional cases
  # .claude/rules/ruby.md has in mind. None is recoverable and the answer to
  # every one is the same: report nothing, and the caller leaves the image
  # hotlinked.
  FAILURES = [
    EOFError, IOError, Net::HTTPBadResponse, Net::ProtocolError,
    OpenSSL::SSL::SSLError, SocketError, SystemCallError, Timeout::Error,
    URI::Error
  ].freeze

  Image = Data.define(:bytes, :content_type)

  def initialize(url, resolver: Destination::RESOLVER)
    @url = url
    @resolver = resolver
  end

  def image
    fetch(url, MAX_REDIRECTS)
  rescue *FAILURES
    nil
  end

  private

  attr_reader :url, :resolver

  def fetch(location, hops_left)
    uri = URI.parse(location)
    address = Destination.new(uri, resolver: resolver).address
    return if address.nil?

    get(uri, address) { |response| result_from(uri, response, hops_left) }
  end

  # Net::HTTP hands the response to a block before reading its body, which
  # is what lets the size cap stop a hostile sender mid-download. #request
  # answers the response rather than the block, so the value returns from
  # here instead.
  #
  # ipaddr dials the address Destination checked. The host still goes in as
  # the address Net::HTTP knows the connection by, so SNI, certificate
  # verification and the Host header all carry the name — which is what a
  # CDN routes on, and what dialling the address directly would throw away.
  def get(uri, address)
    Net::HTTP.start(uri.host, uri.port, use_ssl: uri.scheme == "https",
      ipaddr: address, open_timeout: TIMEOUT, read_timeout: TIMEOUT) do |http|
      http.request(Net::HTTP::Get.new(uri)) { |response| return yield(response) }
    end
  end

  def result_from(uri, response, hops_left)
    return image_from(response) unless response.is_a?(Net::HTTPRedirection)
    return if hops_left.zero? || response["Location"].blank?

    fetch(uri.merge(response["Location"]).to_s, hops_left - 1)
  end

  def image_from(response)
    return unless renderable?(response)

    bytes = capped_body(response)
    return if bytes.nil?

    Image.new(bytes: bytes, content_type: content_type(response))
  end

  # The same allowlist Newsletter::InlineImages applies to a stored blob. An
  # image this app would refuse to serve is not worth fetching.
  def renderable?(response)
    response.is_a?(Net::HTTPOK) &&
      Newsletter::InlineImages::DISPLAYABLE_TYPES.include?(content_type(response))
  end

  def content_type(response)
    response["Content-Type"].to_s.split(";").first.to_s.strip.downcase
  end

  # Content-Length is the sender's claim, so it saves a download when it is
  # honest and is checked again against the bytes when it is not.
  def capped_body(response)
    return if response["Content-Length"].to_i > MAX_BYTES

    bytes = +""
    response.read_body do |chunk|
      bytes << chunk
      return nil if bytes.bytesize > MAX_BYTES
    end
    bytes
  end
end
