namespace :images do
  desc "Measure stored newsletter images that predate Active Storage analysis"
  task analyze: :environment do
    measured = 0
    skipped = 0
    failed = 0

    # Filtered here rather than in SQL: metadata is a JSON column, matching
    # inside it takes a LIKE that reads as a guess, and this runs once against
    # an archive small enough that the saving would be theoretical.
    ActiveStorage::Blob.find_each do |blob|
      # The width, not analyzed?: every stored blob was already analysed
      # while ruby-vips was absent, so it is flagged analysed and carries no
      # size, and Active Storage will never look at it again.
      if blob.metadata["width"].present?
        skipped += 1
        next
      end

      # #analyze writes the metadata through update!, so the record in hand
      # already carries the answer and needs no reload to read it.
      blob.analyze

      if blob.metadata["width"].present?
        measured += 1
      else
        failed += 1
      end
    rescue StandardError => error
      # One image vips cannot open should not stop the rest being measured,
      # but it is worth naming — a blob with no size renders as it does today.
      failed += 1
      puts "  #{blob.id} #{blob.content_type}: #{error.class} #{error.message.truncate(80)}"
    end

    puts "Measured #{measured}, already known #{skipped}, no dimensions #{failed}"
  end
end
