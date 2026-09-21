# The originals archive: everything that has arrived, newest first, a page at
# a time. The edition is what the reader is meant to read; this is what they
# come to when they want the thing itself.
class NewslettersController < ApplicationController
  def index
    @feed = Feed.new(after: cursor)
  end

  private

  # Two plain parameters rather than one encoded string, so the address says
  # what it means. Feed::Cursor answers nothing for anything that does not
  # name a row the archive holds — an edited address, or a link to a row since
  # removed — and a nil cursor is the first page, which is the honest answer
  # for a position that is not there.
  def cursor
    Feed::Cursor.naming(params[:after_kind], params[:after_id])
  end
end
