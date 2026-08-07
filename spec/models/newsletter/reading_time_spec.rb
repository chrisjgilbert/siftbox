require "rails_helper"

RSpec.describe Newsletter::ReadingTime do
  def body_of(word_count)
    "<p>#{Array.new(word_count, 'word').join(' ')}</p>"
  end

  it "reads two hundred words in a minute" do
    result = Newsletter::ReadingTime.new(body_of(200)).minutes

    expect(result).to eq(1)
  end

  it "reads a longer newsletter in proportion" do
    result = Newsletter::ReadingTime.new(body_of(800)).minutes

    expect(result).to eq(4)
  end

  # "0 min" tells the reader nothing, and every newsletter takes some time.
  it "never falls below a minute" do
    result = Newsletter::ReadingTime.new(body_of(5)).minutes

    expect(result).to eq(1)
  end

  it "still reads a minute for an empty body" do
    result = Newsletter::ReadingTime.new("").minutes

    expect(result).to eq(1)
  end

  # A newsletter opens with a stylesheet far longer than its prose, and
  # counting that would put every issue at twenty minutes.
  it "counts the prose rather than the markup around it" do
    html = "<style>#{'a' * 4000}</style>#{body_of(200)}"

    result = Newsletter::ReadingTime.new(html).minutes

    expect(result).to eq(1)
  end
end
