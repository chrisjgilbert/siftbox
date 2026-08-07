require "ipaddr"
require "resolv"

# Whether a download may connect at all, and the address to dial when it
# may.
#
# The URL arrives in email anyone can send and the fetch runs from inside
# the network, so this is the whole of what stands between a newsletter and
# the private side of it: server-side request forgery in its textbook shape.
#
# Answering with the address rather than with a yes is the point. Handing a
# hostname back to Net::HTTP would have it resolve the name a second time,
# and a record on a short TTL can answer differently the second time, once
# every check here has passed.
class Newsletter::ImageDownload::Destination
  SCHEMES = %w[http https].freeze

  # What IPAddr has no predicate for, each of them a way back inside: "this
  # host", carrier-grade NAT, IETF protocol assignments, benchmarking,
  # multicast, and the reserved space above it. The documentation ranges are
  # deliberately absent — unroutable, but no risk, and the specs address one.
  UNROUTABLE = %w[
    0.0.0.0/8 100.64.0.0/10 192.0.0.0/24 198.18.0.0/15 224.0.0.0/4
    240.0.0.0/4 ::/128 ff00::/8
  ].map { |range| IPAddr.new(range) }.freeze

  RESOLVER = ->(host) { Resolv.getaddresses(host) }

  def initialize(uri, resolver: RESOLVER)
    @uri = uri
    @resolver = resolver
  end

  # The address to dial, or nothing at all when this is not somewhere this
  # app will fetch from.
  def address
    return unless SCHEMES.include?(uri.scheme) && uri.host.present?

    resolved_address
  end

  private

  attr_reader :uri, :resolver

  # Every address the name answers with has to pass, not only the one that
  # gets dialled: a host answering with one public address and one private
  # one is still a way in.
  def resolved_address
    addresses = resolver.call(uri.host)
    return if addresses.blank?
    return unless addresses.all? { |candidate| public_address?(candidate) }

    addresses.first
  end

  # An address that will not parse is not one to connect to, which is the
  # same answer as a private one — so this reads as a check rather than as
  # the rescue-and-discard .claude/rules/ruby.md warns about.
  def public_address?(candidate)
    ip = IPAddr.new(candidate.to_s)
    return false if ip.loopback? || ip.private? || ip.link_local?

    UNROUTABLE.none? { |range| range.include?(ip) }
  rescue IPAddr::InvalidAddressError
    false
  end
end
