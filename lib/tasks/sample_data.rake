namespace :sample_data do
  desc "Fill the development feed with newsletters to look at"
  task load: :environment do
    raise "Development only" unless Rails.env.development?

    Newsletter.destroy_all

    SampleData::NEWSLETTERS.each do |attributes|
      Newsletter.create!(attributes.transform_values { |value|
        value.respond_to?(:call) ? value.call : value
      })
    end

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

  NEWSLETTERS = [
    {
      sender_name: "Ruby Weekly",
      sender_email: "peter@rubyweekly.com",
      subject: "Ruby 3.4 lands with a rewritten parser",
      snippet: "The parser rewrite landed this week, and it is the largest " \
               "change to the language's front end in a decade.",
      body_html: BODY,
      received_at: -> { 2.hours.ago }
    },
    {
      sender_name: "This Week in Rails",
      sender_email: "editors@weblog.rubyonrails.org",
      subject: "Solid Queue gets recurring jobs, plus a faster query cache",
      snippet: "Recurring jobs are now part of Solid Queue proper, so most " \
               "apps can drop their scheduler gem.",
      body_html: BODY,
      received_at: -> { 6.hours.ago }
    },
    {
      sender_name: "Postgres Weekly",
      sender_email: "peter@postgresweekly.com",
      subject: "Skip scan lands in Postgres 18",
      snippet: "Multi-column indexes just got considerably more useful for " \
               "queries that skip the leading column.",
      body_html: BODY,
      read_at: -> { 1.hour.ago },
      received_at: -> { 1.day.ago }
    },
    {
      sender_name: "Offscreen",
      sender_email: "kai@offscreenmag.com",
      subject: "On reading things that do not want your attention",
      snippet: "A short argument for media that has no idea whether you " \
               "finished it.",
      body_html: BODY,
      received_at: -> { 3.days.ago }
    },
    {
      sender_name: "The Browser",
      sender_email: "editors@thebrowser.com",
      subject: "Five articles worth your evening",
      snippet: "On lighthouse keepers, a very long bridge, and why nobody " \
               "agrees what a sandwich is.",
      body_html: BODY,
      received_at: -> { 5.days.ago }
    }
  ].freeze
end
