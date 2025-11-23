# frozen_string_literal: true

module ActiveStorageDedup
  module AttachmentExtension
    extend ActiveSupport::Concern

    included do
      belongs_to :blob, class_name: "ActiveStorage::Blob",
                        counter_cache: :reference_count,
                        optional: false

      after_destroy :purge_orphaned_blob, if: :should_manage_lifecycle?
    end

    private

    def purge_orphaned_blob
      return unless ActiveStorageDedup.configuration.auto_purge_orphans
      return unless blob.present?

      Rails.logger.debug "[ActiveStorageDedup] Checking if blob #{blob.id} should be purged (attachment destroyed)"

      blob.reload
      Rails.logger.debug "[ActiveStorageDedup] Blob #{blob.id} reference_count: #{blob.reference_count}"

      if blob.reference_count <= 0
        Rails.logger.info "[ActiveStorageDedup] ♻ Purging orphaned blob #{blob.id} (reference_count: #{blob.reference_count})"
        blob.purge
      else
        Rails.logger.debug "[ActiveStorageDedup] Keeping blob #{blob.id} (still has #{blob.reference_count} reference(s))"
      end
    end

    def should_manage_lifecycle?
      ActiveStorageDedup.configuration.auto_purge_orphans &&
        ActiveStorageDedup.deduplicate_enabled_for?(record, name)
    end
  end
end
