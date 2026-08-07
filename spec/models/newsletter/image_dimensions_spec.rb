require "rails_helper"

RSpec.describe Newsletter::ImageDimensions do
  def attach_image(newsletter, filename: "logo.png", analyse: true)
    blob = ActiveStorage::Blob.create_and_upload!(
      io: File.open(Rails.root.join("spec/fixtures/files/logo.png")),
      filename: filename,
      content_type: "image/png"
    )
    newsletter.inline_images.attach(blob)
    blob.analyze if analyse
    blob
  end

  it "gives the stored size for each image, keyed by the path the body points at" do
    newsletter = create(:newsletter)
    blob = attach_image(newsletter)

    sizes = Newsletter::ImageDimensions.new(newsletter).to_h

    expect(sizes).to eq(newsletter.inline_image_path(blob) => [ 8, 4 ])
  end

  it "skips an image Active Storage has not analysed yet" do
    newsletter = create(:newsletter)
    attach_image(newsletter, analyse: false)

    sizes = Newsletter::ImageDimensions.new(newsletter).to_h

    expect(sizes).to be_empty
  end

  it "is empty for a newsletter with no stored images" do
    newsletter = create(:newsletter)

    sizes = Newsletter::ImageDimensions.new(newsletter).to_h

    expect(sizes).to be_empty
  end
end
