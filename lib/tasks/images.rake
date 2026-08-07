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
      if blob.metadata["width"].present?
        skipped += 1
        next
      end

      blob.analyze
      blob.reload.metadata["width"].present? ? measured += 1 : failed += 1
    rescue StandardError => error
      # One image vips cannot open should not stop the rest being measured,
      # but it is worth naming — a blob with no size renders as it does today.
      failed += 1
      puts "  #{blob.id} #{blob.content_type}: #{error.class} #{error.message.truncate(80)}"
    end

    puts "Measured #{measured}, already known #{skipped}, no dimensions #{failed}"
  end
end
