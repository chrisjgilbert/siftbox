require "rails_helper"
require "fugit"

# The scheduler reads config/recurring.yml in production and nothing reads it
# anywhere else, so a class name that does not resolve or a schedule Fugit
# cannot parse is a mistake whose only symptom is an edition that never
# arrives. These are the checks SolidQueue::RecurringTask makes of the file
# when the scheduler boots, made here against the file itself: the model needs
# its own table to be instantiated at all, and the queue database is not part
# of the test schema.
RSpec.describe "the recurring schedule" do
  def task(key)
    YAML.load_file(Rails.root.join("config/recurring.yml")).fetch("production").fetch(key)
  end

  def schedule(key)
    Fugit.parse(task(key).fetch("schedule"), multi: :fail)
  end

  # Through the reader's own zone rather than the server's, which is the whole
  # question being asked: the same wall-clock time is a different hour UTC in
  # summer than in winter, and the schedule has to follow the clock rather
  # than the offset it happened to be written in.
  def fires_after(key, time)
    schedule(key).next_time(time).to_t.in_time_zone("Europe/London")
  end

  it "composes an edition through a job that exists" do
    composition = task("compose_edition").fetch("class")

    expect(composition.safe_constantize).to eq(Edition::CompositionJob)
  end

  # Fugit parses natural language into several things, and the scheduler
  # accepts only a cron: a schedule it reads as a duration or an interval is
  # rejected when the supervisor boots, which is a deploy that starts and then
  # does not.
  it "composes it on a schedule the scheduler accepts" do
    expect(schedule("compose_edition")).to be_a(Fugit::Cron)
  end

  it "composes it at seven in the morning under Greenwich Mean Time" do
    expect(fires_after("compose_edition", Time.utc(2027, 1, 1)).strftime("%H:%M"))
      .to eq("07:00")
  end

  it "composes it at seven in the morning under British Summer Time too" do
    expect(fires_after("compose_edition", Time.utc(2027, 7, 1)).strftime("%H:%M"))
      .to eq("07:00")
  end

  it "polls the blogs through a job that exists" do
    polling = task("poll_blogs").fetch("class")

    expect(polling.safe_constantize).to eq(Blog::PollJob)
  end

  it "polls them on a schedule the scheduler accepts" do
    expect(schedule("poll_blogs")).to be_a(Fugit::Cron)
  end

  # Away from the top of the hour, where the cleanup task and everything else
  # a host runs on the hour already are. Nothing depends on the exact minute;
  # what matters is that a dozen outbound fetches do not start in the same
  # second as the rest of the machine's work.
  it "polls them away from the top of the hour" do
    expect(fires_after("poll_blogs", Time.utc(2027, 1, 1)).strftime("%M")).to eq("20")
  end
end
