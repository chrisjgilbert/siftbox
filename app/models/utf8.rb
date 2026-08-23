# Bytes from outside, read as UTF-8 without losing the ones that already were.
#
# Both ingest paths need this and neither can assume it: a mail part hands
# back ASCII-8BIT, and a feed arrives as whatever the publisher's server sent.
# One Windows-1252 curly quote inside either fails the INSERT, which loses the
# newsletter or the post exactly as raising would.
#
# tidy_bytes rather than force_encoding alone, and rather than a whole
# transcode: it recodes only the runs that are not valid UTF-8, so a document
# that is UTF-8 apart from one stray byte keeps its other accents.
#
# The dup is not politeness. Mail hands back the same raw_source object every
# call, so force_encoding would re-tag its string in place — and the tag is
# needed, because tidy_bytes finds nothing to repair while the string still
# says binary.
class Utf8
  def initialize(bytes)
    @bytes = bytes
  end

  def text
    ActiveSupport::Multibyte::Unicode.tidy_bytes(
      bytes.dup.force_encoding(Encoding::UTF_8)
    )
  end

  private

  attr_reader :bytes
end
