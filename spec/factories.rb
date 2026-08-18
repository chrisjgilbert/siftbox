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
