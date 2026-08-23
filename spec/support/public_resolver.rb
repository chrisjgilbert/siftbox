# One public address for every spec that has to get past Download's refusal
# to reach anywhere private.
#
# 203.0.113.9 is TEST-NET-3 (RFC 5737): never routable, so nothing can
# accidentally connect, yet unmistakably public to the range checks.
#
# Two shapes because there are two seams. Anything that takes a resolver is
# handed the lambda; Blog::PollJob builds its own fetch and has none, so its
# spec stubs the lookup itself — WebMock does not intercept a hostname
# resolution.
module PublicResolver
  ADDRESS = "203.0.113.9".freeze

  def public_resolver
    ->(_host) { [ ADDRESS ] }
  end

  def resolve_publicly
    allow(Resolv).to receive(:getaddresses).and_return([ ADDRESS ])
  end
end

RSpec.configure do |config|
  config.include PublicResolver
end
