require "rails_helper"

# Muting a blog, and the way back. The other half of removing it: destroy
# takes the posts and the citations naming them, this takes nothing — the
# blog is still polled, its posts still reach the originals archive, and only
# the edition stops hearing from it.
RSpec.describe "Blog silences" do
  it "keeps a signed-out reader from muting a blog" do
    blog = create(:blog)

    post blog_silence_path(blog)

    expect(response).to redirect_to(new_session_path)
    expect(blog.reload).not_to be_silenced
  end

  it "mutes a blog" do
    sign_in
    blog = create(:blog)

    post blog_silence_path(blog)

    expect(blog.reload).to be_silenced
  end

  it "returns the reader to the roster after muting" do
    sign_in
    blog = create(:blog)

    post blog_silence_path(blog)

    expect(response).to redirect_to(subscriptions_url)
  end

  # Muting leaves what was already stored where it is. That is the whole
  # difference from removing, and it is what makes muting reversible.
  it "keeps a muted blog's posts" do
    sign_in
    blog = create(:blog)
    create(:blog_post, blog: blog)

    post blog_silence_path(blog)

    expect(blog.reload.posts.count).to eq(1)
  end

  it "keeps a muted blog on the roster" do
    sign_in
    blog = create(:blog)

    post blog_silence_path(blog)

    expect(Blog.count).to eq(1)
  end

  it "keeps a signed-out reader from unmuting a blog" do
    blog = create(:blog, silenced_at: 1.day.ago)

    delete blog_silence_path(blog)

    expect(response).to redirect_to(new_session_path)
    expect(blog.reload).to be_silenced
  end

  it "unmutes a muted blog" do
    sign_in
    blog = create(:blog, silenced_at: 1.day.ago)

    delete blog_silence_path(blog)

    expect(blog.reload).not_to be_silenced
  end

  it "returns the reader to the roster after unmuting" do
    sign_in
    blog = create(:blog, silenced_at: 1.day.ago)

    delete blog_silence_path(blog)

    expect(response).to redirect_to(subscriptions_url)
  end

  # A stale tab, or the reader pressing twice. The roster is the receipt
  # either way and already says which it is.
  it "leaves a blog that is not muted alone" do
    sign_in
    blog = create(:blog, silenced_at: nil)

    delete blog_silence_path(blog)

    expect(response).to redirect_to(subscriptions_url)
    expect(blog.reload).not_to be_silenced
  end

  it "answers 404 for a blog that does not exist" do
    sign_in

    post blog_silence_path(blog_id: 0)

    expect(response).to have_http_status(:not_found)
  end
end
