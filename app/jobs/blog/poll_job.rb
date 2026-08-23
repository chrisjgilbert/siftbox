# The hourly round of the roster: every blog asked whether it has anything
# new. Scheduled in config/recurring.yml, which is a deploy step and is
# written down as one in docs/deploying.md.
#
# One job for the whole roster rather than one per blog, because the roster is
# a dozen feeds and a conditional request against an unchanged one costs a
# header exchange. If it ever grows enough that a slow blog delays the rest,
# the change is to enqueue a job per blog from here — the polling itself is
# already Blog::Poll's and would not move.
#
# Hourly against a daily edition, so how often this runs only decides how
# stale a post can be when the window closes. An hour is noise against that,
# and it is polite: the etag and last-modified this sends back mean an
# unchanged feed answers 304 with no body at all.
class Blog::PollJob < ApplicationJob
  # One blog when the reader has just added it and is waiting to see it fill
  # in, the whole roster on the hour. An optional argument against the usual
  # rule, because the alternative is a second job repeating this one's rescue,
  # which does the same thing for both.
  def perform(blog = nil)
    return poll(blog) if blog

    Blog.find_each { |followed| poll(followed) }
  end

  private

  # Every blog is polled even when an earlier one raised. A feed answering
  # badly is ordinary — a certificate that expired overnight, a host that has
  # gone away, a body that is not a feed — and letting one of those end the
  # round would cost every blog after it in the iteration order their poll,
  # silently and for reasons having nothing to do with them.
  #
  # Blog::Poll already records an ordinary failure rather than raising, so
  # what reaches here is the unforeseen kind. It is recorded the same way,
  # because from the reader's side the difference between a blog that answered
  # badly and a blog that answered in a way nobody predicted is nothing.
  def poll(blog)
    Blog::Poll.new(blog).save
  rescue StandardError => error
    Rails.logger.error("polling #{blog.feed_url} raised: #{error.message}")
    blog.poll_failed
  end
end
