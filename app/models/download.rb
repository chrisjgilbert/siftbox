require "net/http"
require "zlib"

# One fetch of one URL by this server, bounded in every direction a stranger
# could otherwise push it.
#
# Both ingest paths need the same thing and for the same reason: the address
# comes from outside — an image a newsletter hotlinks, a feed the reader
# subscribed to — and the request goes out from inside this network. Where it
# may go is Destination's question, asked again on every redirect. What is
# left here is the fetch: a ceiling on redirects, a cap on bytes, a wall clock
# over the whole thing, and an optional allowlist of what is worth reading.
class Download
  MAX_REDIRECTS = 3
  TIMEOUT = 5

  # TIMEOUT bounds one connect and one read, which is not the same as
  # bounding the fetch: a host dripping a byte every four seconds resets the
  # read clock forever, and a redirect chain multiplies it by the hops. This
  # is the ceiling on the whole thing, redirects included.
  MAX_DURATION = 20

  # Fetching arbitrary URLs off the public internet fails in a dozen ordinary
  # ways, so these are not the exceptional cases .claude/rules/ruby.md has in
  # mind. None is recoverable and the answer to every one is the same: report
  # nothing, and the caller carries on without whatever it asked for.
  #
  # Zlib::Error among them because Net::HTTP asks for gzip on every request
  # and inflates the body itself, so a contradicted Content-Encoding raises
  # from inside #read_body — and uncaught it would fail the whole job, losing
  # every later fetch in the same run.
  FAILURES = [
    EOFError, IOError, Net::HTTPBadResponse, Net::ProtocolError,
    OpenSSL::SSL::SSLError, SocketError, SystemCallError, Timeout::Error,
    URI::Error, Zlib::Error
  ].freeze

  Body = Data.define(:bytes, :content_type)
  Redirect = Data.define(:location)

  # types is an allowlist of content types worth reading, and nil means read
  # whatever comes back. An image is only worth fetching if this app would
  # serve it, so that caller names four; a feed is served under half a dozen
  # types and plenty of misconfigured spellings besides, and the parser is
  # what decides whether it is really a feed.
  def initialize(url, max_bytes:, types: nil, resolver: Destination::RESOLVER)
    @url = url
    @max_bytes = max_bytes
    @types = types
    @resolver = resolver
  end

  # A hop is answered rather than followed from inside its own connection, so
  # the socket is closed before the next one is dialled instead of a chain
  # holding one open per hop, each with a body nothing ever reads.
  def body
    location = url

    MAX_REDIRECTS.succ.times do
      result = fetch(location)
      return result unless result.is_a?(Redirect)

      location = result.location
    end

    nil
  rescue *FAILURES
    nil
  end

  private

  attr_reader :url, :max_bytes, :types, :resolver

  def fetch(location)
    return if out_of_time?

    uri = URI.parse(location)
    address = Destination.new(uri, resolver: resolver).address
    return if address.nil?

    get(uri, address) { |response| result_from(uri, response) }
  end

  # Net::HTTP hands the response to a block before reading its body, which is
  # what lets the size cap stop a hostile server mid-download. #request
  # answers the response rather than the block, so the value returns from
  # here instead.
  #
  # ipaddr dials the address Destination checked. The host still goes in as
  # the address Net::HTTP knows the connection by, so SNI, certificate
  # verification and the Host header all carry the name — which is what a CDN
  # routes on, and what dialling the address directly would throw away.
  def get(uri, address)
    Net::HTTP.start(uri.hostname, uri.port, use_ssl: uri.scheme == "https",
      ipaddr: address, open_timeout: TIMEOUT, read_timeout: TIMEOUT) do |http|
      http.request(Net::HTTP::Get.new(uri)) { |response| return yield(response) }
    end
  end

  def result_from(uri, response)
    return body_from(response) unless response.is_a?(Net::HTTPRedirection)
    return if response["Location"].blank?

    Redirect.new(location: uri.merge(response["Location"]).to_s)
  end

  def body_from(response)
    return unless worth_reading?(response)

    bytes = capped_body(response)
    return if bytes.nil?

    Body.new(bytes: bytes, content_type: content_type(response))
  end

  def worth_reading?(response)
    response.is_a?(Net::HTTPOK) &&
      (types.nil? || types.include?(content_type(response)))
  end

  def content_type(response)
    response["Content-Type"].to_s.split(";").first.to_s.strip.downcase
  end

  # Content-Length is the server's claim, so it saves a download when it is
  # honest and is checked again against the bytes when it is not. The clock is
  # read here too, because a slow drip never trips either cap.
  def capped_body(response)
    return if response["Content-Length"].to_i > max_bytes

    bytes = +""
    response.read_body do |chunk|
      bytes << chunk
      return nil if bytes.bytesize > max_bytes || out_of_time?
    end
    bytes
  end

  def out_of_time?
    now > deadline
  end

  # Memoised, so the first read starts the clock: the ceiling covers the fetch
  # rather than each hop of it.
  def deadline
    @_deadline ||= now + MAX_DURATION
  end

  def now
    Process.clock_gettime(Process::CLOCK_MONOTONIC)
  end
end
