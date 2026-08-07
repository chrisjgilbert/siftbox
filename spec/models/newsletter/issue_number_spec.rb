require "rails_helper"

RSpec.describe Newsletter::IssueNumber do
  it "reads a hash-prefixed number" do
    result = Newsletter::IssueNumber.new("#742: Frozen string literals").to_s

    expect(result).to eq("742")
  end

  it "reads a number the subject spells out" do
    result = Newsletter::IssueNumber.new("Issue 612 — Action Mailbox routing").to_s

    expect(result).to eq("612")
  end

  it "reads a spelled-out number whatever its case" do
    result = Newsletter::IssueNumber.new("ISSUE 612").to_s

    expect(result).to eq("612")
  end

  # The data strip drops the field rather than inventing a number, so most
  # newsletters show two fields where this one shows three.
  it "has no number when the subject carries none" do
    result = Newsletter::IssueNumber.new("Five articles worth your evening").to_s

    expect(result).to eq("")
  end

  # A year, a version or a price is not an issue number.
  it "ignores a bare number in the subject" do
    result = Newsletter::IssueNumber.new("Ruby 3.4 lands with a new parser").to_s

    expect(result).to eq("")
  end

  it "has no number for an empty subject" do
    expect(Newsletter::IssueNumber.new("").to_s).to eq("")
  end

  # Both forms in one subject. The issue number is the one the list numbered
  # its issue with, not the one in a ranked-list hook further along.
  it "reads the form that comes first in the subject" do
    result = Newsletter::IssueNumber.new("Issue 612 — the #1 thing to know").to_s

    expect(result).to eq("612")
  end

  it "still reads a hash number that comes first" do
    result = Newsletter::IssueNumber.new("#742: issue 3 of a series").to_s

    expect(result).to eq("742")
  end
end
