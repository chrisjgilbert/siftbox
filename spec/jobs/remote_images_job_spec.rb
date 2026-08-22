require "rails_helper"

RSpec.describe Newsletter::RemoteImagesJob do
  it "attaches the newsletter's remote images" do
    newsletter = create(:newsletter)
    remote_images = instance_spy(Newsletter::RemoteImages)
    allow(Newsletter::RemoteImages)
      .to receive(:new).with(newsletter).and_return(remote_images)

    Newsletter::RemoteImagesJob.perform_now(newsletter)

    expect(remote_images).to have_received(:attach)
  end
end
