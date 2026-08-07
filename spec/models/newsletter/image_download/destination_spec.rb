require "rails_helper"

RSpec.describe Newsletter::ImageDownload::Destination do
  # 203.0.113.9 is TEST-NET-3 (RFC 5737): never routable, so nothing can
  # accidentally connect, yet unmistakably public to the range checks here.
  def public_resolver
    ->(_host) { [ "203.0.113.9" ] }
  end

  def address_for(url, resolver: public_resolver)
    Newsletter::ImageDownload::Destination
      .new(URI.parse(url), resolver: resolver).address
  end

  # The address rather than a yes, so the caller dials what was checked
  # instead of resolving the name a second time.
  it "answers the address a public host resolves to" do
    address = address_for("https://cdn.example.com/hero.png")

    expect(address).to eq("203.0.113.9")
  end

  it "answers nothing for a URL that is not http or https" do
    address = address_for("ftp://cdn.example.com/hero.png")

    expect(address).to be_nil
  end

  it "answers nothing for a URL with no host" do
    address = address_for("https:///hero.png")

    expect(address).to be_nil
  end

  it "answers nothing for a host that resolves to a loopback address" do
    address = address_for("https://cdn.example.com/hero.png",
      resolver: ->(_host) { [ "127.0.0.1" ] })

    expect(address).to be_nil
  end

  it "answers nothing for a host that resolves to a private address" do
    address = address_for("https://cdn.example.com/hero.png",
      resolver: ->(_host) { [ "10.0.0.5" ] })

    expect(address).to be_nil
  end

  it "answers nothing for a host that resolves to the cloud metadata address" do
    address = address_for("https://cdn.example.com/hero.png",
      resolver: ->(_host) { [ "169.254.169.254" ] })

    expect(address).to be_nil
  end

  # Answering with one public address and one private one is a way in, not a
  # half-measure, so every address has to pass rather than the one dialled.
  it "answers nothing for a host that mixes a private address in with public ones" do
    address = address_for("https://cdn.example.com/hero.png",
      resolver: ->(_host) { [ "203.0.113.9", "10.0.0.5" ] })

    expect(address).to be_nil
  end

  it "answers nothing for a host that resolves to no address at all" do
    address = address_for("https://cdn.example.com/hero.png",
      resolver: ->(_host) { [] })

    expect(address).to be_nil
  end

  it "answers nothing for a host whose address will not parse" do
    address = address_for("https://cdn.example.com/hero.png",
      resolver: ->(_host) { [ "not-an-address" ] })

    expect(address).to be_nil
  end

  # IPAddr reads all 128 bits, so ::ffff:169.254.169.254 is neither
  # link-local nor loopback to it — while the kernel dials an IPv4-mapped
  # address straight through to the IPv4 address inside it. An AAAA record is
  # the sender's to write, so this is a way to the metadata service unless
  # the mapping is undone before the checks run.
  it "answers nothing for a host whose AAAA record maps the metadata address" do
    address = address_for("https://cdn.example.com/hero.png",
      resolver: ->(_host) { [ "::ffff:169.254.169.254" ] })

    expect(address).to be_nil
  end

  it "answers nothing for a host whose AAAA record maps a loopback address" do
    address = address_for("https://cdn.example.com/hero.png",
      resolver: ->(_host) { [ "::ffff:127.0.0.1" ] })

    expect(address).to be_nil
  end

  # The other spellings that carry an IPv4 address inside an IPv6 one:
  # IPv4-compatible, the NAT64 well-known prefix, and 6to4.
  it "answers nothing for a host that resolves to an IPv4-compatible address" do
    address = address_for("https://cdn.example.com/hero.png",
      resolver: ->(_host) { [ "::127.0.0.1" ] })

    expect(address).to be_nil
  end

  it "answers nothing for a host that resolves through the NAT64 prefix" do
    address = address_for("https://cdn.example.com/hero.png",
      resolver: ->(_host) { [ "64:ff9b::169.254.169.254" ] })

    expect(address).to be_nil
  end

  it "answers nothing for a host that resolves to a 6to4 address" do
    address = address_for("https://cdn.example.com/hero.png",
      resolver: ->(_host) { [ "2002:a9fe:a9fe::1" ] })

    expect(address).to be_nil
  end

  it "answers nothing for a host that resolves to a unique-local address" do
    address = address_for("https://cdn.example.com/hero.png",
      resolver: ->(_host) { [ "fc00::1" ] })

    expect(address).to be_nil
  end

  it "answers the address of a host on global unicast IPv6" do
    address = address_for("https://cdn.example.com/hero.png",
      resolver: ->(_host) { [ "2606:4700::1111" ] })

    expect(address).to eq("2606:4700::1111")
  end

  # URI keeps the brackets on #host and only #hostname takes them off.
  # Handing the bracketed spelling to the resolver refuses an IPv6 literal by
  # accident rather than on purpose, and would have Net::HTTP dial a name no
  # socket can parse.
  it "reads an IPv6 literal without its brackets" do
    asked = []
    resolver = lambda do |host|
      asked << host
      [ host ]
    end

    address_for("https://[2606:4700::1111]/hero.png", resolver: resolver)

    expect(asked).to eq([ "2606:4700::1111" ])
  end

  it "answers nothing for an IPv6 literal naming the loopback address" do
    address = address_for("https://[::1]/hero.png", resolver: ->(host) { [ host ] })

    expect(address).to be_nil
  end
end
