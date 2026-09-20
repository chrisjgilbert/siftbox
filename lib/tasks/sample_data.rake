namespace :sample_data do
  desc "Fill the development archive with newsletters and an edition to look at"
  task load: :environment do
    raise "Development only" unless Rails.env.development?

    # One transaction over the clearing and the writing, the way editions.rake
    # composes: a sample edition that fails to write rolls the load back to
    # what was there, rather than leaving an archive full of newsletters
    # under "No editions yet" — the state this task exists to remove.
    Edition.transaction do
      # Editions first, and not only for tidiness: a newsletter's citations
      # cascade with it, so clearing newsletters alone would leave yesterday's
      # sample editions standing with stories that cite nothing.
      Edition.destroy_all
      Newsletter.destroy_all
      newsletters = SampleData.newsletters.map do |attributes|
        Newsletter.create!(attributes).tap(&:capture_lead_image)
      end

      # The edition cites the newsletters by their place in the list above, so
      # the records go in the order the task listed them rather than being
      # read back. SampleEdition says what it is and why it composes nothing.
      edition = SampleEdition.new(newsletters).write

      puts "Created #{newsletters.length} newsletters " \
        "and edition No. #{edition.number}"
    end
  end
end

module SampleData
  # Two bodies rather than one, so the feed shows the lead item, a thumbnail
  # and the dashed fallback box next to each other — and the reader shows a
  # promoted image on some newsletters and none on others.
  #
  # Lead images are captured from these bodies by the same code that runs at
  # ingest, rather than written straight into the column, so this exercises
  # the real path. The image URLs are hotlinked placeholders, the way a real
  # newsletter's are.
  ARTICLE = <<~HTML.freeze
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

  # The same release from the Rails side, which is the second half of the
  # story the sample edition's lead collapses into one paragraph. The two
  # newsletters the lead cites have to carry one release between them or the
  # README's screenshot is a picture of an edition citing a source that says
  # something else — the one thing this app promises it never does. They agree
  # on what changed and part on what it means, and that is where each half of
  # the parting is: the migration note is above, "most gems will never notice"
  # is here.
  RAILS_ARTICLE = <<~HTML.freeze
    <p>Rails itself needed three lines changed, all of them in generators that
    write Ruby rather than read it. For an application the upgrade is quieter
    still.</p>

    <ul>
      <li>The new error messages arrive for free and name the token that
      failed</li>
      <li>Anything that generates or rewrites Ruby — annotations, fixtures,
      a form builder with an <code>eval</code> in it — is worth a run of the
      test suite before you go</li>
      <li>Bootsnap's compile cache is invalidated once, so the first boot
      after the upgrade is slow and every boot after it is not</li>
    </ul>

    <p>The short version is that most gems will never notice, and the handful
    that will already know who they are.</p>

    <h2>Also this week</h2>

    <p>A fix for eager loading through a polymorphic association, and the
    usual half-dozen documentation improvements.</p>
  HTML

  OPENING = <<~HTML.freeze
    <p>The parser rewrite landed this week, and it is the largest change to
    the language's front end in a decade. Here is what actually changed, and
    what it means for the gems you depend on.</p>

    <h2>What changed</h2>
  HTML

  PLAIN_BODY = (OPENING + ARTICLE).freeze

  # The article is passed in because two of these newsletters cover the same
  # release from different sides, and the opening is what they share.
  def self.illustrated_body(seed, article)
    <<~HTML
      #{OPENING}
      <img src="https://picsum.photos/seed/#{seed}/1200/600"
           alt="A diagram nobody will look at twice">
      #{article}
    HTML
  end

  # A method rather than a constant, so the timestamps below are read when
  # the task runs instead of when Rake loads this file.
  def self.newsletters
    [
      {
        sender_name: "Ruby Weekly",
        sender_email: "peter@rubyweekly.com",
        subject: "#742: Ruby 3.4 lands with a rewritten parser",
        snippet: "The parser rewrite landed this week, and it is the largest " \
                 "change to the language's front end in a decade.",
        body_html: illustrated_body("parser", ARTICLE),
        received_at: 2.hours.ago
      },
      # The second half of the lead story's pair, and the reason it cites two:
      # the same release, read from the Rails side. Subject, snippet and body
      # all say so, because the edition claims they do.
      {
        sender_name: "This Week in Rails",
        sender_email: "editors@weblog.rubyonrails.org",
        subject: "What the new parser changes for your application",
        snippet: "Ruby 3.4's rewritten front end is here, and for most Rails " \
                 "applications the upgrade is quieter than the release note.",
        body_html: illustrated_body("rails", RAILS_ARTICLE),
        received_at: 6.hours.ago
      },
      {
        sender_name: "Postgres Weekly",
        sender_email: "peter@postgresweekly.com",
        subject: "Skip scan lands in Postgres 18",
        snippet: "Multi-column indexes just got considerably more useful for " \
                 "queries that skip the leading column.",
        body_html: PLAIN_BODY,
        received_at: 1.day.ago
      },
      {
        sender_name: "Offscreen",
        sender_email: "kai@offscreenmag.com",
        subject: "On reading things that do not want your attention",
        snippet: "A short argument for media that has no idea whether you " \
                 "finished it.",
        body_html: illustrated_body("offscreen", ARTICLE),
        received_at: 3.days.ago
      },
      {
        sender_name: "The Browser",
        sender_email: "editors@thebrowser.com",
        subject: "Five articles worth your evening",
        snippet: "On lighthouse keepers, a very long bridge, and why nobody " \
                 "agrees what a sandwich is.",
        body_html: PLAIN_BODY,
        received_at: 5.days.ago
      }
    ]
  end
end
