# frozen_string_literal: true

class Product < ActiveRecord::Base
  # Disable deduplication for this attachment
  has_one_attached :photo, deduplicate: false
end
