require "rails_helper"

RSpec.describe Utf8 do
  it "leaves valid UTF-8 as it is" do
    text = Utf8.new("Résumé — naïve").text

    expect(text).to eq("Résumé — naïve")
  end

  it "tags bytes that were only labelled binary" do
    bytes = "Résumé".dup.force_encoding(Encoding::ASCII_8BIT)

    text = Utf8.new(bytes).text

    expect(text.encoding).to eq(Encoding::UTF_8)
    expect(text).to eq("Résumé")
  end

  # A whole transcode would take the accents with it. Recoding only the run
  # that is not valid UTF-8 is what keeps a document that is UTF-8 apart from
  # one stray byte readable.
  it "keeps the accents around a byte that is not UTF-8" do
    bytes = "caf\xE9 littéraire".dup.force_encoding(Encoding::ASCII_8BIT)

    text = Utf8.new(bytes).text

    expect(text).to be_valid_encoding
    expect(text).to include("littéraire")
  end

  # Mail hands back the same raw_source object on every call, so re-tagging
  # it in place would change what the next reader sees.
  it "leaves the bytes it was given untouched" do
    bytes = "Résumé".dup.force_encoding(Encoding::ASCII_8BIT)

    Utf8.new(bytes).text

    expect(bytes.encoding).to eq(Encoding::ASCII_8BIT)
  end
end
