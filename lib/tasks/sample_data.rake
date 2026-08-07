namespace :sample_data do
  # Three of the five carry a lead image, so the feed shows the lead item, a
  # thumbnail and the dashed fallback box next to each other. The URLs are
  # hotlinked placeholders, the way a real newsletter's images are.
  desc "Fill the development feed with newsletters to look at"
  task load: :environment do
    raise "Development only" unless Rails.env.development?

    Newsletter.destroy_all
    SampleData.newsletters.each { |attributes| Newsletter.create!(attributes) }

    puts "Created #{Newsletter.count} newsletters"
  end
end

module SampleData
  BODY = <<~HTML.freeze
    <p>The parser rewrite landed this week, and it is the largest change to
    the language's front end in a decade. Here is what actually changed, and
    what it means for the gems you depend on.</p>

    <h2>What changed</h2>

    <p>The old parser was a single 20,000-line file generated from a grammar
    nobody had touched since 2011. It has been replaced with something
    considerably more approachable.</p>

    <ul>
      <li>Error messages now point at the token that actually failed</li>
      <li>Incremental parsing makes editor tooling viable</li>
      <li>The grammar is a separate, readable artefact</li>
    </ul>

    <p>There is a <a href="https://example.com/migration">migration note</a>
    for anyone doing clever things with <code>RubyVM::AbstractSyntaxTree</code>.</p>

    <blockquote>The best part of this release is the part you will never
    notice.</blockquote>

    <h2>Elsewhere</h2>

    <p>A quieter release, but the connection pool changes are worth reading
    if you run more than a handful of workers.</p>
  HTML

  # A method rather than a constant, so the timestamps below are read when
  # the task runs instead of when Rake loads this file.
  def self.newsletters
    [
      {
        sender_name: "Ruby Weekly",
        sender_email: "peter@rubyweekly.com",
        subject: "Ruby 3.4 lands with a rewritten parser",
        lead_image_url: "https://picsum.photos/seed/parser/1200/600",
        snippet: "The parser rewrite landed this week, and it is the largest " \
                 "change to the language's front end in a decade.",
        body_html: BODY,
        received_at: 2.hours.ago
      },
      {
        sender_name: "This Week in Rails",
        sender_email: "editors@weblog.rubyonrails.org",
        subject: "Solid Queue gets recurring jobs, plus a faster query cache",
        lead_image_url: "https://picsum.photos/seed/queue/800/520",
        snippet: "Recurring jobs are now part of Solid Queue proper, so most " \
                 "apps can drop their scheduler gem.",
        body_html: BODY,
        received_at: 6.hours.ago
      },
      {
        sender_name: "Postgres Weekly",
        sender_email: "peter@postgresweekly.com",
        subject: "Skip scan lands in Postgres 18",
        snippet: "Multi-column indexes just got considerably more useful for " \
                 "queries that skip the leading column.",
        body_html: BODY,
        read_at: 1.hour.ago,
        received_at: 1.day.ago
      },
      {
        sender_name: "Offscreen",
        sender_email: "kai@offscreenmag.com",
        subject: "On reading things that do not want your attention",
        lead_image_url: "https://picsum.photos/seed/offscreen/800/520",
        snippet: "A short argument for media that has no idea whether you " \
                 "finished it.",
        body_html: BODY,
        received_at: 3.days.ago
      },
      {
        sender_name: "The Browser",
        sender_email: "editors@thebrowser.com",
        subject: "Five articles worth your evening",
        snippet: "On lighthouse keepers, a very long bridge, and why nobody " \
                 "agrees what a sandwich is.",
        body_html: BODY,
        received_at: 5.days.ago
      }
    ]
  end
end
