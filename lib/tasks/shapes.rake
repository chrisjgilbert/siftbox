namespace :shapes do
  # A deploy step, once, after the migration that adds the column. The column
  # defaults to false, so until this runs every newsletter already in the
  # archive reads as prose — which is what the reader did with them before,
  # so nothing looks broken in the meantime. It just means the laid-out ones
  # keep reading badly until the archive has been looked at.
  #
  # Safe to run again. The same body gives the same answer.
  desc "Read the layout shape of newsletters stored before the column existed"
  task backfill: :environment do
    scanned = 0
    Newsletter.find_each do |newsletter|
      newsletter.capture_shape
      scanned += 1
    end

    puts "Read #{scanned} newsletters, #{Newsletter.designed_layout.count} laid out by the sender"
  end
end
