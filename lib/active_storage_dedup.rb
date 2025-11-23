# frozen_string_literal: true

require_relative "active_storage_dedup/version"
require_relative "active_storage_dedup/configuration"
require_relative "active_storage_dedup/blob_deduplication"
require_relative "active_storage_dedup/changes_extension"
require_relative "active_storage_dedup/attachment_options"
require_relative "active_storage_dedup/attachment_extension"

module ActiveStorageDedup
  # Background job for deduplication
  autoload :DeduplicationJob, "active_storage_dedup/deduplication_job"
end

# Load Railtie for Rails integration
require_relative "active_storage_dedup/railtie" if defined?(Rails::Railtie)
