require "rails_helper"

RSpec.describe Blog::PollJob do
  it "polls every blog on the roster" do
    resolve_publicly
    first = create(:blog)
    second = create(:blog)
    stub_feed(first, rss_document(rss_item("From the first")))
    stub_feed(second, rss_document(rss_item("From the second")))

    Blog::PollJob.perform_now

    expect(Blog::Post.pluck(:title))
      .to contain_exactly("From the first", "From the second")
  end

  # Raised past Blog::Poll rather than out of the socket, and the difference
  # matters: a SocketError is inside Download::FAILURES, so Blog::Poll records
  # it as an ordinary failed poll and nothing ever reaches the job's rescue.
  # Both examples below would pass with that rescue deleted if they stubbed
  # the network instead. What is being pinned here is the unforeseen kind.
  def poll_raising_for(blog)
    allow(Blog::Poll).to receive(:new).and_call_original
    allow(Blog::Poll).to receive(:new).with(blog).and_raise(ActiveRecord::RecordNotUnique)
  end

  # One blog answering badly is an ordinary Tuesday, and it must not cost the
  # rest of the roster their poll — which is what an exception escaping here
  # would do, since the job would stop at whichever blog raised.
  it "polls the rest of the roster when one blog raises" do
    resolve_publicly
    broken = create(:blog)
    working = create(:blog)
    poll_raising_for(broken)
    stub_feed(working, rss_document(rss_item("From the working one")))

    Blog::PollJob.perform_now

    expect(Blog::Post.pluck(:title)).to eq([ "From the working one" ])
  end

  it "records a blog that raised as failing" do
    broken = create(:blog, failing_since: nil)
    poll_raising_for(broken)

    Blog::PollJob.perform_now

    expect(broken.reload.failing_since).to be_present
  end

  # A blog just added by the reader, who is waiting for it to fill in. The
  # roster is not polled for them — the other blogs were polled on the hour.
  it "polls one blog when it is handed one" do
    resolve_publicly
    added = create(:blog)
    untouched = create(:blog)
    stub_feed(added, rss_document(rss_item("From the new one")))

    Blog::PollJob.perform_now(added)

    expect(added.reload.polled_at).to be_present
    expect(untouched.reload.polled_at).to be_nil
  end

  it "records a blog it was handed as failing when it raises" do
    broken = create(:blog, failing_since: nil)
    poll_raising_for(broken)

    Blog::PollJob.perform_now(broken)

    expect(broken.reload.failing_since).to be_present
  end
end
