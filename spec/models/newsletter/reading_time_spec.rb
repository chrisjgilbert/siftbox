require "rails_helper"

RSpec.describe Newsletter::ReadingTime do
  def body_of(word_count)
    Newsletter::Body.new("<p>#{Array.new(word_count, 'word').join(' ')}</p>")
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
    result = Newsletter::ReadingTime.new(Newsletter::Body.new("")).minutes

    expect(result).to eq(1)
  end

  # A newsletter opens with a stylesheet far longer than its prose, and
  # counting that would put every issue at twenty minutes.
  it "counts the prose rather than the markup around it" do
    html = "<style>#{'a' * 4000}</style><p>#{Array.new(200, 'word').join(' ')}</p>"

    result = Newsletter::ReadingTime.new(Newsletter::Body.new(html)).minutes

    expect(result).to eq(1)
  end

  # The reader hands over the same body Newsletter::LeadImage has already
  # taken the promoted image out of, so that the two share one parse. An
  # image carries no words, but the count has to prove it rather than assume.
  it "counts the same words after the lead image has been removed" do
    html = "<img src=\"https://cdn.example/hero.png\">" \
           "<p>#{Array.new(400, 'word').join(' ')}</p>"
    body = Newsletter::Body.new(html)
    Newsletter::LeadImage.new(body).remainder

    result = Newsletter::ReadingTime.new(body).minutes

    expect(result).to eq(2)
  end
end
