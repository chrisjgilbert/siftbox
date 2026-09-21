require "rails_helper"

RSpec.describe Edition::CompositionJob do
  # The answer a model would send for these newsletters: one story citing
  # every one of them, which is what the editor's completeness check demands.
  def answer(newsletters, posts: [])
    {
      stories: [ {
        headline: "Figma filed", body: "The S-1 landed.", section: "lead",
        newsletter_ids: newsletters.map(&:id), post_ids: posts.map(&:id)
      } ]
    }.to_json
  end

  # The editor stubbed rather than a client faked, in every example but the
  # first: what this job is answerable for is which newsletters it hands over
  # and what it does with the four ways composition can fail, and none of that
  # needs a model answer invented for it.
  def editor_answering
    editor = instance_double(Edition::Editor, compose: build(:edition))
    allow(Edition::Editor).to receive(:new).and_return(editor)

    editor
  end

  def editor_failing(error)
    editor = instance_double(Edition::Editor)
    allow(editor).to receive(:compose).and_raise(error)
    allow(Edition::Editor).to receive(:new).and_return(editor)

    editor
  end

  # Every attempt the job is entitled to, run the way a worker would run them:
  # the first here, then each enqueued retry taken off the queue in turn,
  # carrying its own execution count with it. Not perform_enqueued_jobs, which
  # wraps whatever the last attempt raises in a Minitest error and hides the
  # one thing the example is looking at.
  def run_every_attempt
    Edition::CompositionJob.perform_now
    ActiveJob::Base.execute(enqueued_jobs.shift) while enqueued_jobs.any?
  end

  # Composed for real, through Edition::Window and Edition::Editor, with only
  # the SDK's client swapped for the fake — a job takes serialisable arguments
  # and cannot be handed a client, so this is the seam. The key is set and put
  # back because Edition::Draft reads it on the way to building the client it
  # is about to be given instead, and it fetches rather than reads: absent, as
  # it is here, the example fails on a KeyError about the variable.
  def through(client, &composing)
    allow(Anthropic::Client).to receive(:new).and_return(client)

    with_environment("ANTHROPIC_API_KEY" => "not-a-key", &composing)
  end

  it "publishes an edition covering the newsletters that have arrived" do
    newsletter = create(:newsletter, received_at: 1.hour.ago)

    through(FakeAnthropic.new(text: answer([ newsletter ]))) do
      Edition::CompositionJob.perform_now
    end

    expect(Edition.last.stories.flat_map(&:newsletters)).to eq([ newsletter ])
  end

  # Whole rows, because Edition::Prompt reads body_html — the window is what
  # decides that, and this is the pin that the job passes the window's own
  # newsletters rather than going back to the database for a cheaper set.
  it "hands the editor the window it built" do
    newsletter = create(:newsletter, received_at: 1.hour.ago)
    editor_answering

    Edition::CompositionJob.perform_now

    expect(Edition::Editor)
      .to have_received(:new).with(kind_of(Edition), having_attributes(newsletters: [ newsletter ]))
  end

  it "publishes nothing when no newsletters have arrived since the last edition" do
    create(:edition, window_ended_at: 2.hours.ago)
    create(:newsletter, received_at: 3.hours.ago)

    Edition::CompositionJob.perform_now

    expect(Edition.count).to eq(1)
  end

  # The gap the editor cannot close: its completeness check passes vacuously
  # over no newsletters, so an empty window handed to it composes and
  # publishes an empty edition. The skip is the caller's to make.
  it "does not ask the model to write an edition from an empty window" do
    allow(Edition::Editor).to receive(:new)

    Edition::CompositionJob.perform_now

    expect(Edition::Editor).not_to have_received(:new)
  end

  # A morning with nothing in the window and a morning the job never ran look
  # identical otherwise, and the difference is the one thing worth knowing.
  it "says in the log that the window was empty" do
    allow(Rails.logger).to receive(:info)

    Edition::CompositionJob.perform_now

    expect(Rails.logger).to have_received(:info).with(/nothing has arrived/)
  end

  # Three full-price requests have already been spent on this window. A retry
  # spends three more against the same prompt and the same newsletters, and
  # the mail is covered by tomorrow's window regardless.
  it "does not try again after abandoning an incomplete edition" do
    create(:newsletter, received_at: 1.hour.ago)
    editor_failing(Edition::Editor::Incomplete)

    expect { Edition::CompositionJob.perform_now }
      .not_to have_enqueued_job(Edition::CompositionJob)
  end

  it "tries again later when the model could not be reached" do
    create(:newsletter, received_at: 1.hour.ago)
    editor_failing(Edition::Draft::Unavailable)

    expect { Edition::CompositionJob.perform_now }
      .to have_enqueued_job(Edition::CompositionJob)
  end

  # Bounded, and the bound is the point: an outage that outlasts the first
  # hour of the morning is written down rather than paid for again. Counted
  # off what the job actually does rather than read back off its own
  # declaration.
  #
  # It used to raise here, so the morning showed up as a failed job — the only
  # signal there was that an edition was missing. The gap carries that now,
  # and carries it to the reader rather than only to whoever reads the queue.
  it "gives up once the attempts are spent" do
    create(:newsletter, received_at: 1.hour.ago)
    editor = editor_failing(Edition::Draft::Unavailable)

    run_every_attempt

    expect(editor)
      .to have_received(:compose).exactly(Edition::CompositionJob::ATTEMPTS).times
  end

  # A classifier that declined this window declines it again.
  it "does not try again when the model refused to write the edition" do
    create(:newsletter, received_at: 1.hour.ago)
    editor_failing(Edition::Draft::Refused)

    expect { Edition::CompositionJob.perform_now }
      .not_to have_enqueued_job(Edition::CompositionJob)
  end

  # And a window that ran past the token ceiling runs past it again — worse
  # tomorrow, when the window is a day bigger, which is why it is logged.
  it "does not try again when the edition ran past the token ceiling" do
    create(:newsletter, received_at: 1.hour.ago)
    editor_failing(Edition::Draft::Truncated)

    expect { Edition::CompositionJob.perform_now }
      .not_to have_enqueued_job(Edition::CompositionJob)
  end

  it "does not try again when the API refused the request" do
    create(:newsletter, received_at: 1.hour.ago)
    editor_failing(Edition::Draft::Rejected)

    expect { Edition::CompositionJob.perform_now }
      .not_to have_enqueued_job(Edition::CompositionJob)
  end

  it "logs the reason there is no edition" do
    create(:newsletter, received_at: 1.hour.ago)
    editor_failing(Edition::Draft::Rejected.new("the request was refused: 400"))
    allow(Rails.logger).to receive(:error)

    Edition::CompositionJob.perform_now

    expect(Rails.logger).to have_received(:error).with(/the request was refused: 400/)
  end

  # The unique indexes on number and published_on are what turn a double-fired
  # or concurrent run into a failed insert rather than a second edition for the
  # day. The run that loses has nothing left to do.
  it "stands down when another run published the day's edition first" do
    create(:newsletter, received_at: 1.hour.ago)
    editor_failing(ActiveRecord::RecordNotUnique)

    expect { Edition::CompositionJob.perform_now }
      .not_to have_enqueued_job(Edition::CompositionJob)
  end

  it "publishes an edition covering the posts that have arrived" do
    post = create(:blog_post, received_at: 1.hour.ago)

    through(FakeAnthropic.new(text: answer([], posts: [ post ]))) do
      Edition::CompositionJob.perform_now
    end

    expect(Edition.sole.stories.sole.blog_posts).to eq([ post ])
  end

  # A morning with a post and no mail is not an empty window. Without this the
  # job would skip and the reader would get nothing, on a day their blogs
  # published.
  it "composes an edition on a day only a post arrived" do
    create(:blog_post, received_at: 1.hour.ago)
    editor = editor_answering

    Edition::CompositionJob.perform_now

    expect(editor).to have_received(:compose)
  end

  # Every morning is accounted for by an edition or by a gap, and the
  # watermark is read across both. Without this a window that produced nothing
  # is reconsidered tomorrow, so the next window is bigger — which is how a
  # run of failures aims a multi-day window at a ceiling it cannot clear.
  it "records a gap when the window held nothing" do
    Edition::CompositionJob.perform_now

    expect(Edition::Gap.sole).to be_empty_window
  end

  it "records a gap when the edition could not be composed" do
    create(:newsletter, received_at: 1.hour.ago)
    editor_failing(Edition::Draft::Rejected.new("the request was refused: 400"))

    Edition::CompositionJob.perform_now

    expect(Edition::Gap.sole).to be_failed
  end

  it "keeps the reason beside the gap it explains" do
    create(:newsletter, received_at: 1.hour.ago)
    editor_failing(Edition::Draft::Refused.new("a classifier declined"))

    Edition::CompositionJob.perform_now

    expect(Edition::Gap.sole.detail).to include("a classifier declined")
  end

  it "records a gap when an incomplete edition is abandoned" do
    create(:newsletter, received_at: 1.hour.ago)
    editor_failing(Edition::Editor::Incomplete)

    Edition::CompositionJob.perform_now

    expect(Edition::Gap.sole).to be_failed
  end

  it "records a gap once the retries for an unreachable model are spent" do
    create(:newsletter, received_at: 1.hour.ago)
    editor_failing(Edition::Draft::Unavailable.new("the model could not be reached"))

    run_every_attempt

    expect(Edition::Gap.sole).to be_failed
  end

  # The day has its edition, written by the run that won the race. A gap
  # beside it would have the archive contradict itself.
  it "records no gap when another run published the day's edition first" do
    create(:newsletter, received_at: 1.hour.ago)
    editor_failing(ActiveRecord::RecordNotUnique)

    Edition::CompositionJob.perform_now

    expect(Edition::Gap.count).to be_zero
  end

  it "records no gap on the morning it publishes an edition" do
    create(:newsletter, received_at: 1.hour.ago)
    editor_answering

    Edition::CompositionJob.perform_now

    expect(Edition::Gap.count).to be_zero
  end

  # Composition takes minutes, so the clock has moved by the time a failure
  # handler runs. The gap has to close the window composition actually tried:
  # reading the clock again there would swallow whatever landed while the
  # model was writing, and the next window starts above it.
  it "closes the window composition tried rather than the one the clock moved to" do
    morning = Time.zone.local(2026, 8, 15, 7)
    create(:newsletter, received_at: morning - 1.hour)
    editor = instance_double(Edition::Editor)
    allow(editor).to receive(:compose) do
      travel_to(morning + 3.minutes)
      raise Edition::Draft::Rejected
    end
    allow(Edition::Editor).to receive(:new).and_return(editor)

    travel_to(morning) { Edition::CompositionJob.perform_now }

    expect(Edition::Gap.sole.window_ended_at).to eq(morning)
  end

  # The whole point of the change, end to end: a morning that was tried and
  # could not be answered for still moves the floor, so tomorrow covers a day
  # rather than two. Written against a published edition behind it, because
  # that is where the old behaviour showed — with nothing behind it the window
  # falls back on FIRST_WINDOW and reaches a day either way.
  it "leaves the next window starting where the gap closed" do
    morning = Time.zone.local(2026, 8, 15, 7)
    create(:edition, window_started_at: morning - 2.days, window_ended_at: morning - 1.day)
    create(:newsletter, received_at: morning - 1.hour)
    editor_failing(Edition::Draft::Rejected)

    travel_to(morning) { Edition::CompositionJob.perform_now }

    expect(Edition::Window.new(morning + 1.day).started_at).to eq(morning)
  end
end
