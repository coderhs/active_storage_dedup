# frozen_string_literal: true

module ActiveStorageDedup
  module BlobDeduplication
    extend ActiveSupport::Concern

    class_methods do
      # PRIMARY HOOK: Rails 6.1+ form uploads via Changes::CreateOne
      # This is called by ActiveStorage::Attached::Changes::CreateOne#find_or_build_blob
      def build_after_unfurling(io:, filename:, content_type: nil, metadata: nil,
                                service_name: nil, identify: true,
                                __dedup_record: nil, __dedup_attachment_name: nil, **options)
        Rails.logger.debug "[ActiveStorageDedup] build_after_unfurling called for #{filename}"
        Rails.logger.debug "[ActiveStorageDedup] Context: record=#{__dedup_record&.class&.name}, attachment=#{__dedup_attachment_name}"

        # Build the blob using the original method to get the checksum computed
        blob = super(
          io: io, filename: filename, content_type: content_type,
          metadata: metadata, service_name: service_name, identify: identify, **options
        )

        Rails.logger.debug "[ActiveStorageDedup] Blob built with checksum: #{blob.checksum&.slice(0, 12)}..."

        # Check if deduplication enabled for this attachment
        should_dedup = should_deduplicate?(__dedup_record, __dedup_attachment_name)
        Rails.logger.debug "[ActiveStorageDedup] Deduplication enabled: #{should_dedup}"

        # Check if a blob with this checksum already exists
        if should_dedup && blob.checksum
          actual_service_name = blob.service_name || service.name
          Rails.logger.debug "[ActiveStorageDedup] Checking for duplicates: checksum=#{blob.checksum[0..12]}..., service=#{actual_service_name}"

          if (existing_blob = find_by(checksum: blob.checksum, service_name: actual_service_name))
            Rails.logger.info "[ActiveStorageDedup] ✓ Reusing existing blob #{existing_blob.id} (checksum: #{blob.checksum[0..12]}..., service: #{actual_service_name})"
            return existing_blob
          end

          Rails.logger.debug "[ActiveStorageDedup] No duplicate found, will use new blob"
        end

        Rails.logger.info "[ActiveStorageDedup] Creating new blob for #{filename} (checksum: #{blob.checksum&.slice(0, 12)}...)" if should_dedup
        blob
      end

      # HOOK 2: Direct uploads to cloud storage
      def create_before_direct_upload!(filename:, byte_size:, checksum:, key: nil,
                                       content_type: nil, metadata: nil,
                                       service_name: nil,
                                       __dedup_record: nil, __dedup_attachment_name: nil, **options)
        Rails.logger.debug "[ActiveStorageDedup] create_before_direct_upload! called for #{filename}"
        Rails.logger.debug "[ActiveStorageDedup] Context: record=#{__dedup_record&.class&.name}, attachment=#{__dedup_attachment_name}"
        Rails.logger.debug "[ActiveStorageDedup] Checksum provided by client: #{checksum&.slice(0, 12)}..."

        # Check if deduplication enabled
        should_dedup = should_deduplicate?(__dedup_record, __dedup_attachment_name)
        Rails.logger.debug "[ActiveStorageDedup] Deduplication enabled: #{should_dedup}"

        unless should_dedup
          Rails.logger.debug "[ActiveStorageDedup] Deduplication disabled, creating new blob"
          return super(
            key: key, filename: filename, byte_size: byte_size, checksum: checksum,
            content_type: content_type, metadata: metadata,
            service_name: service_name, **options
          )
        end

        # Checksum already provided by client
        actual_service_name = service_name || service.name
        Rails.logger.debug "[ActiveStorageDedup] Checking for duplicates: checksum=#{checksum[0..12]}..., service=#{actual_service_name}"

        # Check for existing blob
        if (existing_blob = find_by(checksum: checksum, service_name: actual_service_name))
          Rails.logger.info "[ActiveStorageDedup] ✓ Reusing existing blob #{existing_blob.id} for direct upload (checksum: #{checksum[0..12]}..., service: #{actual_service_name})"
          return existing_blob
        end

        Rails.logger.debug "[ActiveStorageDedup] No duplicate found, creating new blob"
        # No duplicate - create new blob
        new_blob = super(
          key: key, filename: filename, byte_size: byte_size, checksum: checksum,
          content_type: content_type, metadata: metadata,
          service_name: service_name, **options
        )
        Rails.logger.info "[ActiveStorageDedup] Created new blob #{new_blob.id} for direct upload #{filename}"
        new_blob
      end

      # HOOK 3: Fallback for programmatic attach (record.file.attach(io: ...))
      def create_after_unfurling!(io:, filename:, key: nil, content_type: nil,
                                  metadata: nil, service_name: nil, identify: true,
                                  __dedup_record: nil, __dedup_attachment_name: nil, **options)
        Rails.logger.debug "[ActiveStorageDedup] create_after_unfurling! called for #{filename}"
        Rails.logger.debug "[ActiveStorageDedup] Context: record=#{__dedup_record&.class&.name}, attachment=#{__dedup_attachment_name}"

        # Check if deduplication enabled
        should_dedup = should_deduplicate?(__dedup_record, __dedup_attachment_name)
        Rails.logger.debug "[ActiveStorageDedup] Deduplication enabled: #{should_dedup}"

        unless should_dedup
          Rails.logger.debug "[ActiveStorageDedup] Deduplication disabled, creating new blob"
          return super(
            key: key, io: io, filename: filename, content_type: content_type,
            metadata: metadata, service_name: service_name, identify: identify, **options
          )
        end

        Rails.logger.debug "[ActiveStorageDedup] Building blob to compute checksum..."
        # Build blob first to get checksum (but don't save yet)
        blob = build_after_unfurling(
          io: io, filename: filename, content_type: content_type,
          metadata: metadata, service_name: service_name, identify: identify,
          __dedup_record: __dedup_record, __dedup_attachment_name: __dedup_attachment_name
        )

        # If build_after_unfurling returned an existing blob, just return it
        if blob.persisted?
          Rails.logger.debug "[ActiveStorageDedup] build_after_unfurling returned existing blob #{blob.id}"
          return blob
        end

        # Otherwise save the new blob
        Rails.logger.debug "[ActiveStorageDedup] Saving new blob..."
        blob.save!
        Rails.logger.info "[ActiveStorageDedup] Created and saved new blob #{blob.id} for #{filename}"
        blob
      end

      private

      def should_deduplicate?(record, attachment_name)
        # If no context, use global setting
        return ActiveStorageDedup.enabled? unless record && attachment_name

        # Check per-attachment setting
        ActiveStorageDedup.deduplicate_enabled_for?(record, attachment_name)
      end
    end
  end
end
