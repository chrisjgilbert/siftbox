require "rails_helper"

RSpec.describe Edition::Story::Body do
  it "reads a body with no breaks in it as one paragraph" do
    body = Edition::Story::Body.new("Levine reads the numbers first.")

    expect(body.blocks.map(&:text)).to eq([ "Levine reads the numbers first." ])
  end

  it "reads a break between two paragraphs as two paragraphs" do
    body = Edition::Story::Body.new("Levine reads the numbers.\n\nThe Diff reads the filing.")

    expect(body.blocks.map(&:text))
      .to eq([ "Levine reads the numbers.", "The Diff reads the filing." ])
  end

  # A model that hard-wraps its prose sends a paragraph as several lines. The
  # break it was asked to write is a blank line, so anything less is a wrap.
  it "closes up a paragraph the editor wrapped across two lines" do
    body = Edition::Story::Body.new("Levine reads the numbers\nfirst.")

    expect(body.blocks.sole.text).to eq("Levine reads the numbers first.")
  end

  it "reads a run of marked lines as one list" do
    body = Edition::Story::Body.new("- Sharding\n- Retries\n- Backpressure")

    expect(body.blocks.sole.items).to eq([ "Sharding", "Retries", "Backpressure" ])
  end

  it "keeps a list between the paragraphs it was written between" do
    body = Edition::Story::Body.new("It covers three things.\n- Sharding\n- Retries\nAn evening's read.")

    expect(body.blocks.map(&:name)).to eq([ "paragraph", "bullets", "paragraph" ])
  end

  # A blank line between two items is how markdown writes a "loose" list, and
  # a model that has read a lot of markdown writes one. It is still one list:
  # taken as several, each restarts the page's counter at 01.
  it "reads a list written with a blank line between its items as one list" do
    body = Edition::Story::Body.new("- Sharding\n\n- Retries\n\n- Backpressure")

    expect(body.blocks.sole.items).to eq([ "Sharding", "Retries", "Backpressure" ])
  end

  it "keeps two lists apart when a paragraph stands between them" do
    body = Edition::Story::Body.new("- Sharding\n\nThen the second half.\n\n- Retries")

    expect(body.blocks.map(&:name)).to eq([ "bullets", "paragraph", "bullets" ])
  end

  # Nothing in this app writes CRLF, but the copy is a JSON string from
  # somewhere else and a body that carried it used to lose every paragraph
  # break silently — which is the wall of text this class exists to undo.
  it "reads a break written with Windows line endings as a break" do
    body = Edition::Story::Body.new("Levine reads it.\r\n\r\nSo does The Diff.")

    expect(body.blocks.map(&:text)).to eq([ "Levine reads it.", "So does The Diff." ])
  end

  # An asterisk and a bullet character are what a model reaches for when it
  # has been asked for a list and not told what to mark it with.
  it "reads an asterisk as a list marker" do
    body = Edition::Story::Body.new("* Sharding\n* Retries")

    expect(body.blocks.sole.items).to eq([ "Sharding", "Retries" ])
  end

  it "reads a bullet character as a list marker" do
    body = Edition::Story::Body.new("• Sharding\n• Retries")

    expect(body.blocks.sole.items).to eq([ "Sharding", "Retries" ])
  end

  # The dashes are punctuation this copy genuinely uses, and a sentence
  # opening on one is a sentence rather than the first item of a list.
  it "reads a line opening on an em dash as prose" do
    body = Edition::Story::Body.new("— and the filing says nothing about it.")

    expect(body.blocks.sole.name).to eq("paragraph")
  end

  # The marker is the marker plus the space after it, so a sentence that is
  # only a hyphen is not half a list item.
  it "reads a line that is only a marker as prose" do
    body = Edition::Story::Body.new("-")

    expect(body.blocks.sole.name).to eq("paragraph")
  end

  it "drops the blank lines a paragraph break is written with" do
    body = Edition::Story::Body.new("Levine reads it.\n\n\n\nSo does The Diff.")

    expect(body.blocks.length).to eq(2)
  end

  it "reads nothing out of a body with nothing in it" do
    body = Edition::Story::Body.new("")

    expect(body.blocks).to be_empty
  end

  # What the terminal transcript prints, and the one place the marker is
  # written back out: the page draws it in CSS instead.
  it "prints a paragraph as the line the editor wrote" do
    body = Edition::Story::Body.new("Levine reads the numbers first.")

    expect(body.blocks.sole.lines).to eq([ "Levine reads the numbers first." ])
  end

  it "prints a list with a marker against each item" do
    body = Edition::Story::Body.new("- Sharding\n- Retries")

    expect(body.blocks.sole.lines).to eq([ "- Sharding", "- Retries" ])
  end
end
