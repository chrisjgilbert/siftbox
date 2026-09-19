require "rails_helper"

RSpec.describe SampleEdition do
  # Five, oldest last, which is the order lib/tasks/sample_data.rake lists
  # them in and the order the sample edition is written against.
  def sample_newsletters
    (1..5).map { |days| create(:newsletter, received_at: days.days.ago) }
  end

  # The completeness guarantee the real editor is held to, held here by
  # construction: a screenshot of an edition that quietly left a newsletter
  # out would be a picture of the bug the editor exists to refuse.
  it "writes one edition citing every sample newsletter" do
    newsletters = sample_newsletters

    SampleEdition.new(newsletters).write

    expect(Edition.count).to eq(1)
    expect(Edition.sole.stories.flat_map(&:newsletters)).to match_array(newsletters)
  end

  # The page draws three sections and drops any the edition has nothing for,
  # so a sample missing one would show a page with a section missing.
  it "files a story in each section" do
    newsletters = sample_newsletters

    edition = SampleEdition.new(newsletters).write

    expect(edition.stories.map(&:section).uniq).to match_array(Edition::Story::SECTIONS)
  end

  # The one column that says how an edition came to read this way. A row the
  # model never wrote must never claim a model wrote it.
  it "marks the edition as a sample" do
    newsletters = sample_newsletters

    edition = SampleEdition.new(newsletters).write

    expect(edition.editor_model).to eq("sample")
  end
end
