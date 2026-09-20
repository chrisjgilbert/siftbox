# The project page — the only part of this app a signed-out visitor can
# reach. It reads and writes nothing: there is no hosted siftbox to sign up
# for, so the page says what this is and points at the source.
class LandingsController < ApplicationController
  allow_unauthenticated_access only: :show

  def show
    redirect_to reader_home_url if authenticated?
  end

  private

  # Home for a signed-in reader is the day's briefing: root serves the latest
  # edition, and the originals are an archive behind it rather than the first
  # thing the app shows.
  #
  # Before the first edition is composed there is nothing to serve, and the
  # editions archive is where the app says when to expect one. Sending a
  # reader to the inbox instead would make the empty morning look like the
  # design. Read through for_archive because a redirect wants an id, not the
  # model's whole answer in raw_response.
  def reader_home_url
    edition = Edition.for_archive.latest
    return editions_url unless edition

    edition_url(edition)
  end
end
