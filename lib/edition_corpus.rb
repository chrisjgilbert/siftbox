# Seven synthetic newsletters and what an edition composed from them should
# contain — a test set with known expectations, not filler.
#
# It exists because the reader chose to start the editor on synthetic mail
# rather than wait for a key, so until the backtest task is pointed at real
# newsletters this corpus is the only evidence composition works at all. That
# only holds if the expectations are written down somewhere a spec can read
# them, which is what #stories and each item's #nature are: the edition a
# perfect editor would have written from this window.
#
# Everything in it is fabricated — the companies, the products, the numbers,
# the senders and their domains. Deliberately: a real event lets a model
# answer from what it already knows about it, which is the one thing the
# prompt forbids, and an invented one can only be reported from the bodies
# below. The three newsletters covering the Tessera relicence disagree on
# three checkable points (the benchmark figure, how much of the code converts,
# how many maintainers left), because "where sources disagree, say so rather
# than resolving it" is untestable against sources that agree.
#
# Development and test material. It is not loaded by anything the reader's
# browser reaches.
module EditionCorpus
  NEWS = :news
  EVERGREEN = :evergreen
  TEASER = :teaser

  # Not a nature the editor ever classifies: mail held in the pen never
  # reaches it. Recorded here because the corpus has to be able to say that a
  # newsletter's expected treatment is to be seen by nobody.
  CONFIRMATION = :confirmation

  # One newsletter, with what it is and which story it belongs to. The
  # attributes are what Newsletter takes, so the only difference between a
  # corpus newsletter and an ingested one is where the body came from.
  Item = Data.define(:key, :nature, :story, :attributes) do
    def confirmation?
      nature == CONFIRMATION
    end

    # The pen is enforced by two validations rather than by a check
    # constraint, so this goes through #hold rather than writing held_at into
    # the attributes above — the same reason the PRD's backfill has to call
    # the verb. Held at creation because the live path flags at ingest, before
    # any edition window has had a chance to see it.
    def ingest
      newsletter = Newsletter.create!(attributes)
      newsletter.hold if confirmation?

      newsletter
    end
  end

  # One entry of the edition this corpus should produce: where it belongs, and
  # roughly what it should say. The headline and body are ground truth in the
  # weak sense — a real editor's wording will differ and should — but the
  # section, the clustering and the notes they carry are the expectations
  # Milestone 0 judges an answer against, and they are what the composition
  # spec's fake answers.
  Story = Data.define(:key, :section, :headline, :body)

  # Boilerplate every issue of every newsletter carries, which is what
  # Newsletter::Prose exists to take back off. It is here rather than left out
  # because a corpus of clean bodies would test extraction against mail nobody
  # sends.
  def self.footer(name)
    <<~HTML
      <hr>
      <p style="font-size:12px;color:#8a8a8a">
        You're receiving this because you subscribed to #{name}.
        <a href="https://example.invalid/u/9f2">Unsubscribe</a> |
        <a href="https://example.invalid/p/9f2">Update your preferences</a>
      </p>
      <p style="font-size:12px;color:#8a8a8a">&copy; 2026 #{name}. All rights reserved.</p>
      <img src="https://example.invalid/o/9f2.gif" width="1" height="1" alt="">
    HTML
  end

  STACK_WEEKLY_BODY = <<~HTML.freeze
    <div style="display:none;max-height:0;overflow:hidden">
      Plus: what the four-year clock actually starts on.&#8203;&#8203;&#8203;&#8203;
    </div>

    <p style="text-align:center;font-size:12px">
      <a href="https://example.invalid/web/742">View this email in your browser</a>
    </p>

    <h1>Tessera 1.0, and a licence nobody expected on release day</h1>

    <p>Halcyon Systems tagged Tessera 1.0 on Tuesday morning, four years after
    the first public commit, and by the afternoon the repository's LICENSE file
    had been replaced. The core moves from Apache 2.0 to the Business Source
    Licence, with each release converting back to Apache four years after it
    ships.</p>

    <p>Taking the release on its own terms first, because it is a good one. The
    write path has been rebuilt around a group commit scheme, and Halcyon's
    published numbers put mixed read/write throughput at <strong>3.1x</strong>
    the 0.9 series on their reference machine. Range scans are roughly
    unchanged. The long-standing complaint about vacuum pauses on high-churn
    tables is addressed directly, and in our own poking at the release
    candidate the pauses are gone rather than shortened.</p>

    <h2>What the licence does and does not stop</h2>

    <p>If you run Tessera yourself, for your own product, nothing changes. The
    additional use grant is broad: the only thing the BSL forbids is offering
    Tessera itself as a managed service. Nadia Okonjo, Halcyon's CTO, was
    blunt about why in a post published alongside the release.</p>

    <blockquote>A hyperscaler has been reselling Tessera as a managed service
    for two years without contributing a line back. We built the thing. We are
    not going to fund somebody else's margin on it.</blockquote>

    <p>The four-year conversion is the part worth holding onto: 1.0 becomes
    Apache 2.0 in 2030 whatever happens to Halcyon in the meantime, which is
    more than most relicensing announcements offer.</p>

    <p>There is talk of a fork in the usual places. We will believe it when
    there is CI attached to it.</p>

    #{footer("The Stack Weekly")}
  HTML

  KERNEL_NOTES_BODY = <<~HTML.freeze
    <p style="text-align:center;font-size:12px">
      <a href="https://example.invalid/web/88">Read in browser</a> &middot;
      <a href="https://example.invalid/app">Read in the app</a>
    </p>

    <h1>What Halcyon's benchmark actually measured</h1>

    <p>Everyone has covered the Tessera relicence by now. Almost nobody has
    run the benchmark, so we did.</p>

    <p>Halcyon's 3.1x is real in the sense that we reproduced it exactly: on a
    96-core machine, with <code>fsync</code> disabled, against a workload that
    is 90% reads. Turn fsync back on, which is the configuration anyone
    storing money or orders is obliged to run, and the same comparison on the
    same hardware gives <strong>1.4x</strong>. On a more ordinary 16-core box
    it is 1.15x. That is a decent release. It is not the number in the
    announcement, and the announcement does not say which configuration it
    used.</p>

    <h2>The part of the licence post that got skipped</h2>

    <p>The four-year conversion applies to the storage engine. The cluster
    manager — the piece that makes Tessera something other than a very good
    single-node database — has moved to a separate repository under a
    proprietary licence with no conversion clause at all. It is not coming
    back in 2030 or ever. Halcyon's post mentions this in a footnote and every
    write-up we have read has repeated the headline instead.</p>

    <p>On the reselling: Halcyon named no vendor, and we cannot find a managed
    Tessera service offered by anyone. We asked. We were told the company had
    nothing further to add.</p>

    <h2>Mosaic</h2>

    <p>The fork is called Mosaic and is now on its own infrastructure. Three
    of the eleven listed Tessera maintainers have signed the announcement.
    They have committed to the last Apache-licensed commit as their starting
    point, which is the correct and boring choice.</p>

    #{footer("Kernel Notes")}
  HTML

  SUBSTRATE_BODY = <<~HTML.freeze
    <p style="text-align:center;font-size:12px">
      <a href="https://example.invalid/web/31">View online</a>
    </p>

    <h1>The Series B that came with a licence attached</h1>

    <p>The Tessera relicence has been reported this week as a response to
    something: a hyperscaler, a competitor, a moment of vendor bad faith.
    Two people with direct knowledge of Halcyon Systems' funding tell a
    different story, and the dates support them.</p>

    <p>Halcyon closed a 40m Series B in March, led by Kestrel Partners. Both
    people say a move off a permissive licence before general availability was
    a term of the round rather than a reaction to anything that happened
    after it. One describes the reselling explanation as "the version that
    tests well". Halcyon declined to comment. Kestrel did not respond.</p>

    <h2>What it has cost so far</h2>

    <p>Seven of the eleven maintainers listed on the Tessera repository in
    January have left Halcyon. Four have gone to the Mosaic fork; three have
    taken jobs elsewhere and have said nothing publicly. Halcyon has hired two
    engineers onto the team since.</p>

    <p>Mosaic starts from the last Apache-licensed commit with no funding, no
    build infrastructure of its own beyond what the four have paid for
    personally, and a cluster manager it does not have and cannot copy. The
    goodwill is entirely with them. Goodwill has never once paid for a release
    engineer.</p>

    <p>The uncomfortable read is that this worked. Halcyon has its licence,
    its round and a product most of its users will keep running, and the cost
    was a fork that may not survive the year.</p>

    #{footer("Substrate")}
  HTML

  WHITEBOARD_BODY = <<~HTML.freeze
    <div style="display:none;max-height:0;overflow:hidden">
      Part three of the sharding series.&#8203;&#8203;&#8203;
    </div>

    <h1>Consistent hashing, drawn out properly</h1>

    <p>This is part three of the sharding series, and like the others it is
    entirely diagrams. Nothing here is new, nothing here is news, and none of
    it will be obsolete next month.</p>

    <p>Start with the problem. You have twelve cache nodes and a key. The
    obvious answer is <code>hash(key) % 12</code>, and it is correct until the
    day you have thirteen nodes, at which point almost every key moves. Figure
    1 shows that: two rows of keys, before and after, with the ones that stay
    put in grey. There are four of them.</p>

    <figure>
      <img src="https://example.invalid/img/ring-1.png"
           alt="Figure 1: key placement under modulo hashing before and after a node is added">
      <figcaption>Figure 1. Adding one node to a modulo scheme moves nearly
      every key.</figcaption>
    </figure>

    <p>Now the ring. Hash the nodes onto the same space as the keys, and give
    each key to the first node clockwise of it. Figure 2 is the whole idea in
    one picture, and if you take nothing else from this issue, take the
    picture. Adding a node now interrupts exactly one arc, so only the keys in
    that arc move. Removing one merges its arc into its neighbour's.</p>

    <figure>
      <img src="https://example.invalid/img/ring-2.png"
           alt="Figure 2: keys and nodes hashed onto a ring, each key assigned clockwise">
      <figcaption>Figure 2. The ring. Each key belongs to the first node
      clockwise of it.</figcaption>
    </figure>

    <p>The naive ring has an unfairness problem: with twelve nodes hashed onto
    a ring, the arcs are not the same size, and the unluckiest node routinely
    holds three or four times its share. The fix is virtual nodes — hash each
    physical node onto the ring a hundred or two hundred times. Figure 3 plots
    the load spread against the number of virtual nodes, and the curve flattens
    around 150, which is where most implementations sit and why.</p>

    <figure>
      <img src="https://example.invalid/img/ring-3.png"
           alt="Figure 3: load imbalance falling as virtual nodes per physical node increases">
      <figcaption>Figure 3. Imbalance against virtual nodes per physical node.</figcaption>
    </figure>

    <h2>Two exercises</h2>

    <ol>
      <li>Twelve nodes, 150 virtual nodes each, one node fails. What fraction
      of keys move, and where do they go? Draw it before you calculate it.</li>
      <li>Your ring is fine and one key is still hot. Consistent hashing does
      not fix this. Why not, and what does?</li>
    </ol>

    <p>Next issue: bounded-load consistent hashing, which is the answer to
    exercise two and needs a diagram of its own.</p>

    #{footer("The Whiteboard")}
  HTML

  MARGIN_NOTES_BODY = <<~HTML.freeze
    <h1>The port contract nobody can explain (part one)</h1>

    <p>In November the Harbour Authority awarded a 2.1bn automation contract
    for the eastern terminals to Calder Freight Systems. The award is public,
    the scoring summary is public, and I have spent six weeks with both. There
    are three things in them that do not work. This week, the first, which is
    the only one you can check yourself in an afternoon.</p>

    <h2>One: the bid arrived four months late</h2>

    <p>The tender closed on 14 March. Calder's submission is date-stamped 19
    July. The authority's own procurement rules allow a late submission only
    where the tender is reopened and every bidder is notified, and there is no
    notice of reopening in the register — I checked every entry between March
    and August, twice. The two bidders who submitted on time were not told the
    window had moved, because on paper it never did.</p>

    <p>The scoring summary treats all three bids as though they arrived
    together. Calder's is scored highest on delivery confidence, which is a
    judgement, and on price, which is not.</p>

    <h2>Two: the price that changed after scoring</h2>

    <p>The second reason is where this stops being administrative. Calder's
    own filings, published a fortnight after the award, put the contract value
    at 2.34bn — a quarter of a billion above the figure the bid was scored on.
    There are two ways that happens and only one of them is</p>

    <hr>

    <p style="text-align:center">
      <strong>This post is for paying subscribers.</strong><br>
      Part two goes through the filings line by line, with the documents
      attached.
    </p>

    <p style="text-align:center">
      <a href="https://example.invalid/upgrade">Upgrade to keep reading</a><br>
      <a href="https://example.invalid/signin">Already a subscriber? Sign in</a>
    </p>

    #{footer("Margin Notes")}
  HTML

  QUERY_PLAN_BODY = <<~HTML.freeze
    <p style="text-align:center;font-size:12px">
      <a href="https://example.invalid/web/211">View this email in your browser</a>
    </p>

    <h1>#211: Skiplist indexes land in Corvid 4.2</h1>

    <p>Corvid 4.2 was released on Monday. The headline is skiplist indexes,
    which are aimed squarely at tables that churn: queue tables, session
    tables, anything where the b-tree spends its life being rebalanced by
    deletes.</p>

    <p>Two things worth knowing before you reach for one. The planner will
    choose a skiplist index on its own from 4.2 — there is no hint and no
    setting, which is the right call and does mean plans can change under you
    on upgrade. And the index cannot be built in place: an existing b-tree has
    to be dropped and recreated, which on a large table is the whole
    maintenance window.</p>

    <p>Point releases for 4.1 and 4.0 went out the same day with the usual
    correctness fixes. The 3.x line is now out of support.</p>

    #{footer("Query Plan Weekly")}
  HTML

  CONFIRMATION_BODY = <<~HTML.freeze
    <h1>One more click</h1>

    <p>Someone — hopefully you — asked to subscribe to <strong>The
    Whiteboard</strong> with this address. Confirm it and the next issue will
    arrive as usual.</p>

    <p style="text-align:center">
      <a href="https://example.invalid/confirm/8c41f0"
         style="background:#111;color:#fff;padding:12px 24px">Yes, subscribe me</a>
    </p>

    <p>This link expires in 24 hours. If you did not ask for this, ignore this
    email and nothing will happen.</p>

    <p style="font-size:12px;color:#8a8a8a">
      Sent by Dispatchmail on behalf of The Whiteboard.<br>
      Dispatchmail, 41 Blackfriars Road, London SE1 8NZ
    </p>
  HTML

  # The items and the stories are built on each call rather than held in a
  # constant, because their received_at has to be read when the corpus is
  # ingested and not when Rails loaded this file — the same reason
  # SampleData.newsletters is a method.
  def self.items
    [
      stack_weekly, kernel_notes, substrate, whiteboard, margin_notes,
      query_plan, whiteboard_confirmation
    ]
  end

  def self.stories
    [ tessera, consistent_hashing, port_contract, skiplist_indexes ]
  end

  def self.story(key)
    stories.detect { |story| story.key == key }
  end

  def self.sources(story)
    items.select { |item| item.story == story.key }
  end

  # Returns the newsletters by the name the corpus knows them, because both
  # callers need to get from an expectation back to the row it is about: the
  # spec to write the ids into the fake's answer, the backtest task to say
  # which sender a citation points at.
  def self.ingest
    items.to_h { |item| [ item.key, item.ingest ] }
  end

  def self.stack_weekly
    Item.new(
      key: :stack_weekly, nature: NEWS, story: :tessera,
      attributes: {
        sender_name: "The Stack Weekly",
        sender_email: "editors@thestackweekly.dev",
        subject: "Tessera 1.0 ships, and changes licence on the way out",
        snippet: "Halcyon shipped 1.0 on Tuesday and moved the whole thing to " \
                 "the BSL the same afternoon.",
        body_html: STACK_WEEKLY_BODY,
        received_at: 20.hours.ago
      }
    )
  end

  def self.kernel_notes
    Item.new(
      key: :kernel_notes, nature: NEWS, story: :tessera,
      attributes: {
        sender_name: "Kernel Notes",
        sender_email: "dispatch@kernelnotes.dev",
        subject: "What Halcyon's benchmark actually measured",
        snippet: "We reran it on hardware people own. 1.4x, not 3.1x — and " \
                 "the cluster manager isn't coming back.",
        body_html: KERNEL_NOTES_BODY,
        received_at: 14.hours.ago
      }
    )
  end

  def self.substrate
    Item.new(
      key: :substrate, nature: NEWS, story: :tessera,
      attributes: {
        sender_name: "Substrate",
        sender_email: "ivo@substrate.works",
        subject: "The Series B that came with a licence attached",
        snippet: "Two people close to Halcyon's March round say relicensing " \
                 "was a term, not a response.",
        body_html: SUBSTRATE_BODY,
        received_at: 6.hours.ago
      }
    )
  end

  def self.whiteboard
    Item.new(
      key: :whiteboard, nature: EVERGREEN, story: :consistent_hashing,
      attributes: {
        sender_name: "The Whiteboard",
        sender_email: "hello@whiteboardweekly.email",
        subject: "Consistent hashing, drawn out properly",
        snippet: "Three diagrams and about twenty-five minutes. No news in " \
                 "here at all.",
        body_html: WHITEBOARD_BODY,
        received_at: 9.hours.ago
      }
    )
  end

  def self.margin_notes
    Item.new(
      key: :margin_notes, nature: TEASER, story: :port_contract,
      attributes: {
        sender_name: "Margin Notes",
        sender_email: "notes@marginnotes.co",
        subject: "The port contract nobody can explain (part one)",
        snippet: "Calder Freight won 2.1bn on a bid four months late. The " \
                 "first reason that doesn't add up is public.",
        body_html: MARGIN_NOTES_BODY,
        received_at: 11.hours.ago
      }
    )
  end

  def self.query_plan
    Item.new(
      key: :query_plan, nature: NEWS, story: :skiplist_indexes,
      attributes: {
        sender_name: "Query Plan Weekly",
        sender_email: "peter@queryplanweekly.dev",
        subject: "#211: Skiplist indexes land in Corvid 4.2",
        snippet: "Corvid 4.2 is out with skiplist indexes, and the planner " \
                 "will pick them on its own.",
        body_html: QUERY_PLAN_BODY,
        received_at: 3.hours.ago
      }
    )
  end

  # No story and no section: the expectation for this one is that no edition
  # ever mentions it. It comes from the sending platform rather than from The
  # Whiteboard itself, which is what makes the first-time-sender guard almost
  # always true for a genuine confirmation.
  def self.whiteboard_confirmation
    Item.new(
      key: :whiteboard_confirmation, nature: CONFIRMATION, story: nil,
      attributes: {
        sender_name: "Dispatchmail",
        sender_email: "no-reply@dispatchmail.com",
        subject: "Confirm your subscription to The Whiteboard",
        snippet: "One more click and you're subscribed. This link expires in " \
                 "24 hours.",
        body_html: CONFIRMATION_BODY,
        received_at: 22.hours.ago
      }
    )
  end

  def self.tessera
    Story.new(
      key: :tessera, section: Edition::Story::LEAD,
      headline: "Halcyon relicenses Tessera as 1.0 ships",
      body: "Halcyon Systems released Tessera 1.0 on Tuesday and moved it off " \
            "Apache 2.0 to the Business Source Licence the same day. The three " \
            "newsletters that covered it agree on the release and on almost " \
            "nothing else. The Stack Weekly reports Halcyon's own figure of 3.1x " \
            "the throughput of 0.9 on a mixed workload; Kernel Notes reran the " \
            "benchmark with fsync on and got 1.4x, and says only the storage " \
            "engine converts to Apache after four years while the cluster " \
            "manager stays closed for good. On why: Halcyon told The Stack " \
            "Weekly a hyperscaler was reselling Tessera without contributing " \
            "back, though Kernel Notes could not find such a service; Substrate " \
            "reports two people close to Halcyon's March Series B saying the " \
            "relicence was a term of the round. The fork, Mosaic, is real — " \
            "Kernel Notes counts three maintainers signing its announcement, " \
            "Substrate says seven of eleven have left Halcyon altogether."
    )
  end

  def self.consistent_hashing
    Story.new(
      key: :consistent_hashing, section: Edition::Story::READING_LIST,
      headline: "The Whiteboard: consistent hashing, drawn out properly",
      body: "A patient, diagram-led walk through consistent hashing: the ring, " \
            "why virtual nodes exist, and what actually moves when a node " \
            "leaves. It assumes you have met hashing and nothing else, builds " \
            "the whole thing in three figures, and ends with two exercises " \
            "rather than a conclusion. Around twenty-five minutes, and worth an " \
            "evening if you have ever nodded along to \"we shard by user id\" " \
            "without being able to draw it. The figures are the piece; there is " \
            "no summary of this that leaves anything behind."
    )
  end

  def self.port_contract
    Story.new(
      key: :port_contract, section: Edition::Story::BRIEFLY,
      headline: "Margin Notes starts on the Calder port contract",
      body: "Margin Notes opens a series on the 2.1bn port automation contract " \
            "awarded to Calder Freight Systems, whose bid arrived four months " \
            "after the stated deadline. The free portion covers the first of " \
            "three objections — the deadline itself; the rest is paywalled and " \
            "the email stops mid-sentence on the second."
    )
  end

  def self.skiplist_indexes
    Story.new(
      key: :skiplist_indexes, section: Edition::Story::BRIEFLY,
      headline: "Corvid 4.2 adds skiplist indexes",
      body: "Query Plan Weekly reports Corvid 4.2, out Monday, with skiplist " \
            "indexes for high-churn tables and a planner that will choose them " \
            "without a hint. Upgrades are in place; the index has to be rebuilt."
    )
  end
end
