class AddLeadImageUrlToNewsletters < ActiveRecord::Migration[8.0]
  # "" rather than nil for "no image in email", which is what the feed's
  # dashed fallback box renders and what every other string column on this
  # table already does. Nothing queries or sorts on it, so no index.
  def change
    add_column :newsletters, :lead_image_url, :string, default: "", null: false
  end
end
