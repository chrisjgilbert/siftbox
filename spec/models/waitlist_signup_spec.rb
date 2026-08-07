require "rails_helper"

RSpec.describe WaitlistSignup do
  it "joins the list with a real address" do
    signup = WaitlistSignup.new(email: "reader@example.com")

    result = signup.join

    expect(result).to be(true)
  end

  it "records the address it joined with" do
    signup = WaitlistSignup.new(email: "reader@example.com")

    signup.join

    expect(WaitlistSignup.pluck(:email)).to eq([ "reader@example.com" ])
  end

  it "refuses an address that is not one" do
    signup = WaitlistSignup.new(email: "not-an-address")

    result = signup.join

    expect(result).to be(false)
  end

  it "refuses an empty address" do
    expect(WaitlistSignup.new(email: "").join).to be(false)
  end

  it "records nothing for an address it refused" do
    signup = WaitlistSignup.new(email: "not-an-address")

    signup.join

    expect(WaitlistSignup.count).to eq(0)
  end

  it "normalises case and surrounding space" do
    signup = WaitlistSignup.new(email: "  Reader@Example.COM ")

    signup.join

    expect(WaitlistSignup.pluck(:email)).to eq([ "reader@example.com" ])
  end

  # Telling a visitor their address is already on the list answers a question
  # about someone else's address.
  it "treats an address already on the list as a success" do
    WaitlistSignup.create!(email: "reader@example.com")

    result = WaitlistSignup.new(email: "reader@example.com").join

    expect(result).to be(true)
  end

  it "keeps one row for an address that joins twice" do
    WaitlistSignup.create!(email: "reader@example.com")

    WaitlistSignup.new(email: "reader@example.com").join

    expect(WaitlistSignup.count).to eq(1)
  end

  it "catches a duplicate that differs only in case" do
    WaitlistSignup.create!(email: "reader@example.com")

    WaitlistSignup.new(email: "READER@example.com").join

    expect(WaitlistSignup.count).to eq(1)
  end

  # A 422 would tell a bot which field caught it, so a filled honeypot looks
  # exactly like a successful signup and writes nothing.
  it "reports success when the honeypot has been filled" do
    signup = WaitlistSignup.new(email: "bot@example.com", website: "https://spam.example")

    result = signup.join

    expect(result).to be(true)
  end

  it "records nothing when the honeypot has been filled" do
    signup = WaitlistSignup.new(email: "bot@example.com", website: "https://spam.example")

    signup.join

    expect(WaitlistSignup.count).to eq(0)
  end
end
