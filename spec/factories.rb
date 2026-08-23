FactoryBot.define do
  factory :edition do
    sequence(:number)
    # Sequenced like the number beside it, and for the same reason: both
    # columns are uniquely indexed, so a constant here makes every example
    # that builds two editions supply dates by hand to dodge a collision it
    # did not set out to test.
    sequence(:published_on) { |n| Date.current - n.days }
    published_at { Time.current }
    window_started_at { 1.day.ago }
    window_ended_at { Time.current }
  end

  factory :blog do
    title { "Query Plan Weekly" }
    sequence(:feed_url) { |n| "https://queryplanweekly#{n}.dev/feed" }
  end

  # Long enough to clear Blog::Post::EDITORIAL_MINIMUM, because a post that
  # carries its article is the ordinary case and a stub is the exception. A
  # spec that wants the exception says so by passing a short body.
  factory :blog_post, class: "Blog::Post" do
    blog
    title { "Why your index is not being used" }
    received_at { 1.hour.ago }
    body_html do
      "<p>The planner will not reach for a partial index unless the query " \
        "repeats the index's own predicate, which is easy to miss because " \
        "nothing warns you about it. The plan simply comes back as a scan, " \
        "and a scan over a table small enough to fit in cache is fast " \
        "enough that nobody notices until the table is not small any more. " \
        "What follows is four months of watching that happen, and the two " \
        "lines of SQL that turned it back into a seek. The planner is not " \
        "wrong to do it, and that is the part worth sitting with: a scan is " \
        "cheaper than a seek right up until the table stops fitting in " \
        "memory, and nothing anywhere announces the day it stops. The fix " \
        "was to repeat the predicate. The lesson was that a partial index " \
        "is a promise the query has to make too, and that an index nobody " \
        "is using looks exactly like an index nobody needs.</p>"
    end
  end

  factory :edition_citation, class: "Edition::Citation" do
    newsletter
    story factory: :edition_story
  end

  factory :edition_story, class: "Edition::Story" do
    edition
    sequence(:position)
    section { Edition::Story::LEAD }
    body { "Money Stuff and The Diff both read the Figma S-1." }
  end

  factory :newsletter do
    sender_name { "Ruby Weekly" }
    sender_email { "peter@rubyweekly.com" }
    subject { "Ruby 3.4 lands with a new parser" }
    received_at { 1.hour.ago }
  end

  factory :user do
    email_address { "reader@example.com" }
    password { "a-long-enough-password" }
  end

  factory :waitlist_signup do
    email { "reader@example.com" }
  end
end
