# frozen_string_literal: true

module ActiveStorageDedup
  class Railtie < ::Rails::Railtie
    # Use after_initialize for reliable patching
    config.after_initialize do
      ActiveStorageDedup.logger.info "[ActiveStorageDedup] Initializing ActiveStorageDedup gem..."

      # Patch ActiveStorage::Blob with deduplication hooks
      ActiveSupport.on_load(:active_storage_blob) do
        ActiveStorageDedup.logger.debug "[ActiveStorageDedup] Patching ActiveStorage::Blob with BlobDeduplication module"
        # Prepend deduplication module to singleton class (for class methods)
        # Using prepend allows us to use 'super' to call the original methods
        ActiveStorage::Blob.singleton_class.prepend(
          ActiveStorageDedup::BlobDeduplication::ClassMethods
        )
        ActiveStorageDedup.logger.debug "[ActiveStorageDedup] ✓ ActiveStorage::Blob patched successfully"
      end

      # Patch ActiveStorage::Attachment with counter cache and lifecycle
      ActiveSupport.on_load(:active_storage_attachment) do
        ActiveStorageDedup.logger.debug "[ActiveStorageDedup] Patching ActiveStorage::Attachment with AttachmentExtension module"
        include ActiveStorageDedup::AttachmentExtension
        ActiveStorageDedup.logger.debug "[ActiveStorageDedup] ✓ ActiveStorage::Attachment patched successfully"
      end

      # Patch Changes::CreateOne to pass context (Rails 6.0+)
      if defined?(ActiveStorage::Attached::Changes::CreateOne)
        ActiveStorageDedup.logger.debug "[ActiveStorageDedup] Patching ActiveStorage::Attached::Changes::CreateOne with ChangesExtension module"
        ActiveStorage::Attached::Changes::CreateOne.prepend(
          ActiveStorageDedup::ChangesExtension
        )
        ActiveStorageDedup.logger.debug "[ActiveStorageDedup] ✓ ActiveStorage::Attached::Changes::CreateOne patched successfully"
      else
        ActiveStorageDedup.logger.debug "[ActiveStorageDedup] ActiveStorage::Attached::Changes::CreateOne not found, skipping patch"
      end

      # Extend ActiveRecord with has_attached options
      ActiveSupport.on_load(:active_record) do
        ActiveStorageDedup.logger.debug "[ActiveStorageDedup] Extending ActiveRecord with AttachmentOptions module"
        extend ActiveStorageDedup::AttachmentOptions
        ActiveStorageDedup.logger.debug "[ActiveStorageDedup] ✓ ActiveRecord extended successfully"
      end

      ActiveStorageDedup.logger.info "[ActiveStorageDedup] ✓ Gem initialization complete"
    end
  end
end
