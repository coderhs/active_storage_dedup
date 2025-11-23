# frozen_string_literal: true

ActiveStorageDedup.configure do |config|
  # Master switch to enable/disable the entire gem
  # Set to false to completely disable deduplication and lifecycle management
  # Default: true
  config.enabled = true

  # Default deduplication setting for all attachments
  # When enabled=true, this controls whether attachments deduplicate by default
  # Can be overridden per-attachment using: has_many_attached :images, deduplicate: false
  # Default: true
  config.deduplicate_by_default = true

  # Automatically purge orphaned blobs when reference_count reaches 0
  # When enabled, blobs are automatically deleted when no attachments reference them
  # Default: true
  config.auto_purge_orphans = true
end

# Usage Examples:
#
# Opt-out pattern (deduplicate everything except specific attachments):
#   config.enabled = true
#   config.deduplicate_by_default = true
#
#   class Product < ApplicationRecord
#     has_many_attached :images                         # Deduplicates (uses default)
#     has_one_attached :unique_badge, deduplicate: false # Does NOT deduplicate (override)
#   end
#
# Opt-in pattern (only deduplicate specific attachments):
#   config.enabled = true
#   config.deduplicate_by_default = false
#
#   class Product < ApplicationRecord
#     has_many_attached :images, deduplicate: true      # Deduplicates (override)
#     has_one_attached :avatar                          # Does NOT deduplicate (uses default)
#   end
#
# Disable gem entirely (useful for development/testing):
#   config.enabled = false
