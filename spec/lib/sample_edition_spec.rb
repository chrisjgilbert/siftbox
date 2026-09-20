require "rails_helper"

RSpec.describe SampleEdition do
  # Oldest last, which is the order lib/tasks/sample_data.rake lists them in
  # and the order the sample edition is written against. The task lists five.
  def sample_newsletters(count)
    (1..count).map { |days| create(:newsletter, received_at: days.days.ago) }
  end

  # The completeness guarantee the real editor is held to, held here by
  # construction: a screenshot of an edition that quietly left a newsletter
  # out would be a picture of the bug the editor exists to refuse.
  it "writes one edition citing every sample newsletter" do
    newsletters = sample_newsletters(5)

    SampleEdition.new(newsletters).write

    expect(Edition.count).to eq(1)
    expect(Edition.sole.stories.flat_map(&:newsletters))
      .to match_array(newsletters)
  end

  # The same guarantee from the other side. The stories cite the task's list
  # by position, so a newsletter added to that list has no story until one is
  # written here, and the task has to fail on it rather than write an edition
  # that leaves it out.
  it "refuses a newsletter no story cites" do
    newsletters = sample_newsletters(6)

    expect { SampleEdition.new(newsletters).write }
      .to raise_error(ArgumentError)
  end

  # The page draws three sections and drops any the edition has nothing for,
  # so a sample missing one would show a page with a section missing.
  it "files a story in each section" do
    newsletters = sample_newsletters(5)

    edition = SampleEdition.new(newsletters).write

    expect(edition.stories.map(&:section).uniq)
      .to match_array(Edition::Story::SECTIONS)
  end

  # config.autoload_lib puts lib/ on the eager-load path, so this class is
  # resident in every production process and a console there is one line away
  # from filing a fabricated edition in the live archive — taking the next
  # real edition number and the day's unique published_on with it. The rake
  # task that calls it guards itself; this is the guard the class carries
  # wherever it is called from.
  it "refuses to write anywhere but a local environment" do
    newsletters = sample_newsletters(5)
    allow(Rails).to receive(:env)
      .and_return(ActiveSupport::EnvironmentInquirer.new("production"))

    expect { SampleEdition.new(newsletters).write }
      .to raise_error(SampleEdition::OutsideDevelopment)
  end

  # The one column that says how an edition came to read this way. A row the
  # model never wrote must never claim a model wrote it.
  it "marks the edition as a sample" do
    newsletters = sample_newsletters(5)

    edition = SampleEdition.new(newsletters).write

    expect(edition.editor_model).to eq("sample")
  end
end
