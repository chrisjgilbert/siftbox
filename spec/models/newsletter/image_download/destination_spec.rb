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
end
