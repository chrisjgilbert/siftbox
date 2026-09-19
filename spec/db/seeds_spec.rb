require "rails_helper"

# `db:prepare` loads the seeds whenever it creates the database, which on a
# deployed host is the first container boot. The guard is what stops a missing
# variable aborting that boot before the app is reachable.
RSpec.describe "db/seeds" do
  # The seeds read the two variables as they run, so a value set for the
  # example's duration is what they see. Set and put back rather than stubbed,
  # the way `through` does in spec/jobs/edition/composition_job_spec.rb: ENV is
  # process-wide, and an example that left a reader behind would decide what
  # every later one seeds. Assigning nil deletes the variable, which is how the
  # absent cases are written.
  def with_reader(email_address:, password:)
    original_email_address = ENV["SIFTBOX_READER_EMAIL"]
    original_password = ENV["SIFTBOX_READER_PASSWORD"]
    ENV["SIFTBOX_READER_EMAIL"] = email_address
    ENV["SIFTBOX_READER_PASSWORD"] = password

    yield
  ensure
    ENV["SIFTBOX_READER_EMAIL"] = original_email_address
    ENV["SIFTBOX_READER_PASSWORD"] = original_password
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

  it "creates the reader account from the environment" do
    with_reader(email_address: "reader@example.com", password: "a-long-enough-password") do
      load_seeds
    end

    expect(User.pluck(:email_address)).to eq([ "reader@example.com" ])
  end

  it "sets a password the reader can sign in with" do
    with_reader(email_address: "reader@example.com", password: "a-long-enough-password") do
      load_seeds
    end

    expect(User.sole.authenticate("a-long-enough-password")).to be_truthy
  end

  it "creates nothing when both variables are absent" do
    with_reader(email_address: nil, password: nil) do
      load_seeds
    end

    expect(User.count).to eq(0)
  end

  it "creates nothing when the email address is missing" do
    with_reader(email_address: nil, password: "a-long-enough-password") do
      load_seeds
    end

    expect(User.count).to eq(0)
  end

  it "creates nothing when the password is missing" do
    with_reader(email_address: "reader@example.com", password: nil) do
      load_seeds
    end

    expect(User.count).to eq(0)
  end

  # Seeds run again on any later db:prepare, and the reader may have changed
  # their password through the reset flow since. Rewriting it here would lock
  # them out of the only account.
  it "leaves an existing account's password alone" do
    User.create!(email_address: "reader@example.com", password: "the-password-in-use")

    with_reader(email_address: "reader@example.com", password: "a-different-password") do
      load_seeds
    end

    expect(User.sole.authenticate("the-password-in-use")).to be_truthy
  end
end
