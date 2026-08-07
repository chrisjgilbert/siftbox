require "rails_helper"

# `db:prepare` loads the seeds whenever it creates the database, which on a
# deployed host is the first container boot. The guard is what stops a missing
# credential aborting that boot before the app is reachable.
RSpec.describe "db/seeds" do
  def stub_reader(reader)
    credentials = Rails.application.credentials

    allow(credentials).to receive(:reader).and_return(reader)
  end

  # Seeds report to stdout, which is worth having during a deploy and not in
  # the spec output.
  def load_seeds
    original = $stdout
    $stdout = StringIO.new
    Rails.application.load_seed
  ensure
    $stdout = original
  end

  it "creates the reader account from credentials" do
    stub_reader(email_address: "reader@example.com", password: "a-long-enough-password")

    load_seeds

    expect(User.pluck(:email_address)).to eq([ "reader@example.com" ])
  end

  it "sets a password the reader can sign in with" do
    stub_reader(email_address: "reader@example.com", password: "a-long-enough-password")

    load_seeds

    expect(User.sole.authenticate("a-long-enough-password")).to be_truthy
  end

  it "creates nothing when the credential is absent" do
    stub_reader(nil)

    load_seeds

    expect(User.count).to eq(0)
  end

  it "creates nothing when the email address is missing" do
    stub_reader(password: "a-long-enough-password")

    load_seeds

    expect(User.count).to eq(0)
  end

  it "creates nothing when the password is missing" do
    stub_reader(email_address: "reader@example.com")

    load_seeds

    expect(User.count).to eq(0)
  end

  # Seeds run again on any later db:prepare, and the reader may have changed
  # their password through the reset flow since. Rewriting it here would lock
  # them out of the only account.
  it "leaves an existing account's password alone" do
    User.create!(email_address: "reader@example.com", password: "the-password-in-use")
    stub_reader(email_address: "reader@example.com", password: "a-different-password")

    load_seeds

    expect(User.sole.authenticate("the-password-in-use")).to be_truthy
  end
end
