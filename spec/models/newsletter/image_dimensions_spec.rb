require "rails_helper"

RSpec.describe Newsletter::ImageDimensions do
  # identify: false so the stored type is the one asked for here. Active
  # Storage otherwise sniffs the bytes, and the bytes are a PNG in every case
  # — including the one testing what happens to a type this app will not
  # serve.
  def attach_image(newsletter, content_type: "image/png", analyse: true)
    blob = ActiveStorage::Blob.create_and_upload!(
      io: StringIO.new(Rails.root.join("spec/fixtures/files/logo.png").binread),
      filename: "logo.png",
      content_type: content_type,
      identify: false
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

  # Newsletters::ImagesController answers 404 for a type it will not serve, so
  # a size here would reserve a column-wide gap for an image that never loads.
  it "skips an image this app will not serve" do
    newsletter = create(:newsletter)
    attach_image(newsletter, content_type: "image/svg+xml")

    sizes = Newsletter::ImageDimensions.new(newsletter).to_h

    expect(sizes).to be_empty
  end

  it "is empty for a newsletter with no stored images" do
    newsletter = create(:newsletter)

    sizes = Newsletter::ImageDimensions.new(newsletter).to_h

    expect(sizes).to be_empty
  end
end
