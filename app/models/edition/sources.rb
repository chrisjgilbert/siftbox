# Everything one edition is written from: the mail that reached the reader in
# its window, and the blog posts that did.
#
# Two collections rather than one merged list, and deliberately so. The
# editor cites them into different columns, and the prompt introduces them
# differently — "Platformer reports" is a sentence about a newsletter, and
# writing it over a blog post would attribute an essay to a mailing list. A
# merged list would have every reader of it start by splitting it again.
#
# What is here is only what treats them as one thing: whether there is
# anything at all to write from.
class Edition::Sources
  def initialize(newsletters:, posts:)
    @newsletters = newsletters
    @posts = posts
  end

  attr_reader :newsletters, :posts

  # Asked before an edition is built, because the PRD skips an empty window
  # silently and Edition::Editor cannot: its completeness check passes
  # vacuously over nothing and it would publish an empty edition.
  def empty?
    newsletters.empty? && posts.empty?
  end
end
