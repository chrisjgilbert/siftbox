namespace :lead_images do
  # A deploy step, once, after the migration that adds the column. Without it
  # every newsletter already in the archive renders the feed's "no image in
  # email" box, because nothing has read their stored bodies yet.
  #
  # Safe to run again. The same body gives the same answer, and newsletters
  # that genuinely carry no image simply stay at "".
  desc "Read the lead image out of newsletters stored before the column existed"
  task backfill: :environment do
    scanned = Newsletter.without_lead_image.count
    Newsletter.without_lead_image.find_each(&:capture_lead_image)

    puts "Scanned #{scanned} newsletters with no lead image captured"
  end
end
