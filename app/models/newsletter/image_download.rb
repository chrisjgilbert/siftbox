require "ipaddr"
require "net/http"
require "resolv"

# One image a newsletter hotlinks, fetched by this server at ingest so the
# reader's browser never asks the sender for it.
#
# The URL arrives in email anyone can send, and the fetch runs from inside
# the network — server-side request forgery in its textbook shape. Hence the
# checks: http and https only, and only addresses on the public internet,
# tested against what the name resolves to rather than how it is spelled,
# and tested again on every redirect. Then a ceiling on redirects, a cap on
# bytes, and only the image types the reader renders.
class Newsletter::ImageDownload
  MAX_BYTES = 5.megabytes
  MAX_REDIRECTS = 3
  SCHEMES = %w[http https].freeze
  TIMEOUT = 5

  # What IPAddr has no predicate for, each of them a way back inside: "this
  # host", carrier-grade NAT, IETF protocol assignments, benchmarking,
  # multicast, and the reserved space above it. The documentation ranges are
  # deliberately absent — unroutable, but no risk, and the specs address one.
  UNROUTABLE = %w[
    0.0.0.0/8 100.64.0.0/10 192.0.0.0/24 198.18.0.0/15 224.0.0.0/4
    240.0.0.0/4 ::/128 ff00::/8
  ].map { |range| IPAddr.new(range) }.freeze

  # Fetching arbitrary URLs off the public internet fails in a dozen
  # ordinary ways, so these are not the exceptional cases
  # .claude/rules/ruby.md has in mind. None is recoverable and the answer to
  # every one is the same: report nothing, and the caller leaves the image
  # hotlinked.
  FAILURES = [
    EOFError, IOError, IPAddr::InvalidAddressError, Net::HTTPBadResponse,
    Net::ProtocolError, OpenSSL::SSL::SSLError, SocketError, SystemCallError,
    Timeout::Error, URI::Error
  ].freeze

  RESOLVER = ->(host) { Resolv.getaddresses(host) }

  Image = Data.define(:bytes, :content_type)

  def initialize(url, resolver: RESOLVER)
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
    return unless allowed?(uri)

    get(uri) { |response| result_from(uri, response, hops_left) }
  end

  # Net::HTTP hands the response to a block before reading its body, which
  # is what lets the size cap stop a hostile sender mid-download. #request
  # answers the response rather than the block, so the value returns from
  # here instead.
  def get(uri)
    Net::HTTP.start(uri.host, uri.port, use_ssl: uri.scheme == "https",
      open_timeout: TIMEOUT, read_timeout: TIMEOUT) do |http|
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

  def allowed?(uri)
    SCHEMES.include?(uri.scheme) && uri.host.present? && public_host?(uri.host)
  end

  # Every address the name answers with, not just the first: a host that
  # resolves to one public address and one private one is still a way in.
  def public_host?(host)
    addresses = resolver.call(host)

    addresses.present? && addresses.all? { |address| public_address?(address) }
  end

  def public_address?(address)
    ip = IPAddr.new(address.to_s)
    return false if ip.loopback? || ip.private? || ip.link_local?

    UNROUTABLE.none? { |range| range.include?(ip) }
  end
end
