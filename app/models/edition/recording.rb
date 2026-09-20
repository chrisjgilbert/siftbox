# An edition read aloud: the audio, and what happened while it was being made.
#
# Made on demand rather than every morning. Composition costs the same whether
# anybody reads the edition or not, but a recording nobody plays is money for
# nothing — so nothing is recorded until a reader presses play, and once
# recorded it is kept, because a second listen should cost nothing and the
# archive is the app's memory.
#
# Three timestamps rather than a status column, per .claude/rules/database.md.
# They are read as three questions the page asks in order: is it ready, did it
# fail, or is it still being made.
class Edition::Recording < ApplicationRecord
  # What the vendor sends and what the controller serves. Held here rather than
  # on Edition::Voice because it is a property of the stored blob: the thing
  # that writes it and the thing that serves it have to agree, and only one of
  # them talks to a vendor.
  AUDIO_TYPE = "audio/mpeg".freeze

  # Deliberately not touched, for the reason Edition::Story gives: an edition
  # is written once at composition and immutable after, and a recording made
  # weeks later would otherwise bump the edition's updated_at to say so.
  belongs_to :edition

  # The blob goes when the row goes, which is Active Storage's own default for
  # has_one_attached and is what the migration's cascade assumes.
  has_one_attached :audio

  validates :edition, uniqueness: true
  validates :requested_at, presence: true

  # A reader has asked to hear this edition. Creates the recording or picks up
  # the one already there, clears whatever happened last time, and hands the
  # work to a job.
  #
  # Enqueued here rather than in the controller, the way Blog::Subscription and
  # Newsletter::InboundMessage enqueue theirs: the controller's job is to answer
  # the request, and what asking for a recording involves is this class's to
  # know.
  #
  # Two taps in the same second — which a button with no JavaScript disabling it
  # invites, especially on a phone — both read an empty table, both pass the
  # uniqueness validation against it, and the second insert fails on the index.
  # The loser has nothing left to do: a recording is already being made and a
  # job is already going to make it, so it answers with the row that won rather
  # than with a 500. Recovered rather than discarded — the caller still gets a
  # recording, which is what it asked for.
  def self.start(edition)
    recording = find_or_initialize_by(edition: edition)
    recording.update!(requested_at: Time.current, failed_at: nil)
    Edition::RecordingJob.perform_later(recording)

    recording
  rescue ActiveRecord::RecordNotUnique
    find_by!(edition: edition)
  end

  # Both stamps written in one update: a retry that works has to clear the
  # failure as well as record the success, or the page would draw a player and
  # offer to make it again underneath.
  def store(bytes, voice:)
    audio.attach(io: StringIO.new(bytes), filename: filename, content_type: AUDIO_TYPE)
    update!(voice: voice, completed_at: Time.current, failed_at: nil)
  end

  def abandon
    update!(failed_at: Time.current)
  end

  # The stamp and the blob, not the stamp alone. A purged blob leaves the
  # completion behind, and a page that trusted the stamp would draw a player
  # with no source in it.
  def ready?
    completed_at.present? && audio.attached?
  end

  def failed?
    failed_at.present?
  end

  def pending?
    !ready? && !failed?
  end

  private

  # What a reader gets if they save the file, so it names the edition rather
  # than the row.
  def filename
    "edition-#{edition.number}.mp3"
  end
end
